//
//  MenuTableViewController.m
//  XLData ( https://github.com/xmartlabs/XLData )
//
//  Copyright (c) 2015 Xmartlabs ( http://xmartlabs.com )
//
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


#import <AFNetworking/AFNetworking.h>
#import "XLDataLoader.h"

NSString * const XLDataLoaderErrorDomain = @"XLDataLoaderErrorDomain";
NSString * const kXLRemoteDataLoaderDefaultKeyForNonDictionaryResponse = @"data";

@interface XLDataLoader()
{
    NSURLSessionDataTask * _task;
}

@property NSUInteger expiryTimeInterval;
@property NSDictionary * loadedData;
@property NSString * offsetParamName;
@property NSString * limitParamName;
@property NSString * searchStingParamName;

@end

@implementation XLDataLoader


// configutration properties
@synthesize expiryTimeInterval = _expiryTimeInterval;

// page paroperties
@synthesize offset = _offset;
@synthesize limit = _limit;

// searchString
@synthesize searchString = _searchString;


-(instancetype)initWithDelegate:(id<XLDataLoaderDelegate>)delegate URLString:(NSString *)urlString
{
    self = [super init];
    if (self){
        [self setDefaultValues];
        self.delegate = delegate;
        _URLString = urlString;
        _offsetParamName = @"offset";
        _limitParamName = @"limit";
        _searchStingParamName = @"search";
        _limit = 0;
    }
    return self;
}

-(instancetype)initWithDelegate:(id<XLDataLoaderDelegate>)delegate URLString:(NSString *)urlString offsetParamName:(NSString *)offsetParamName limitParamName:(NSString *)limitParamName searchStringParamName:(NSString *)searchStringParamName
{
    self = [self initWithDelegate:delegate URLString:urlString];
    if (self){
        self.offsetParamName = offsetParamName;
        self.limitParamName = limitParamName;
        self.searchStingParamName = searchStringParamName;
    }
    return self;
}

-(void)setDefaultValues
{
    _task = nil;
    _offset = 0;
    _loadedData = nil;
    _isLoadingData = NO;
    _hasMoreToLoad = YES;
}

-(NSDictionary *)getParameters
{
    NSMutableDictionary * result = [self.parameters mutableCopy];
    if (self.limit != 0){
        [result addEntriesFromDictionary:@{self.offsetParamName : @(self.offset), self.limitParamName : @(self.limit) }];
    }
    if (self.searchString.length > 0){
        [result addEntriesFromDictionary:@{self.searchStingParamName : self.searchString }];
    }
    return result;
}

-(BOOL)isLoadingData
{
    return _isLoadingData;
}

-(BOOL)hasMoreToLoad
{
    return _hasMoreToLoad;
}

-(NSArray *)loadedDataItems
{
    if (self.loadedData){
        return [self.loadedData valueForKeyPath:self.collectionKeyPath];
    }
    return nil;
}

-(NSURLSessionDataTask *)prepareURLSessionTask
{
    NSMutableURLRequest * request = self.prepareURLRequest;
    XLDataLoader * __weak weakSelf = self;
    return [[self.delegate sessionManagerForDataLoader:self] dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
        if (error) {
            if (responseObject){
                NSMutableDictionary * newUserInfo = [error.userInfo mutableCopy];
                [newUserInfo setObject:responseObject forKey:AFNetworkingTaskDidCompleteSerializedResponseKey];
                NSError * newError = [NSError errorWithDomain:error.domain code:error.code userInfo:newUserInfo];
                [weakSelf unsuccessulDataLoadWithError:newError];
            }
            else{
                [weakSelf unsuccessulDataLoadWithError:error];
            }
        } else {
            NSDictionary * data = [responseObject isKindOfClass:[NSDictionary class]] ? responseObject : @{ weakSelf.collectionKeyPath : responseObject };
            if ([self.delegate respondsToSelector:@selector(dataLoader:convertJsonItemToModelObject:)]){
                NSMutableArray * convertedData = [[NSMutableArray alloc] init];
                [[data valueForKeyPath:self.collectionKeyPath] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    [convertedData addObject:[self.delegate dataLoader:self convertJsonItemToModelObject:obj]];
                }];
                [data setValue:convertedData forKeyPath:self.collectionKeyPath];
            }
            self.loadedData = data;
            [weakSelf successulDataLoad];
            // notify via delegate
            if (weakSelf.delegate){
                [weakSelf.delegate dataLoaderDidLoadData:self];
            }
        }
    }];
}

-(NSMutableURLRequest *)prepareURLRequest
{
    NSError * error;
    AFHTTPSessionManager * sessionManager = [self.delegate sessionManagerForDataLoader:self];
    return [sessionManager.requestSerializer requestWithMethod:@"GET" URLString:[[NSURL URLWithString:self.URLString relativeToURL:sessionManager.baseURL] absoluteString] parameters:[self getParameters] error:&error];
}


-(void)successulDataLoad
{
    _isLoadingData = NO;
    _hasMoreToLoad = (self.limit != 0 && (self.loadedDataItems.count >= self.limit));
}

-(void)unsuccessulDataLoadWithError:(NSError *)error
{
    // change flags
    _isLoadingData = NO;
    
    // notify via delegate
    if (self.delegate){
        [self.delegate dataLoaderDidFailLoadData:self withError:error];
    }
}

-(void)cancelRequest
{
    [_task cancel];
    _task = nil;
}

-(void)load
{
    if (!_isLoadingData){
        _isLoadingData = YES;
        _task = [self prepareURLSessionTask];
        [_task resume];
        if (self.delegate){
            [self.delegate dataLoaderDidStartLoadingData:self];
        }
    }
}


-(void)forceLoad:(BOOL)defaultValues
{
    if (_task){
        [self cancelRequest];
    }
    if (defaultValues){
        [self setDefaultValues];
    }
    [self load];
}


#pragma mark - Properties

-(NSString *)collectionKeyPath
{
    if (_collectionKeyPath) return _collectionKeyPath;
    return kXLRemoteDataLoaderDefaultKeyForNonDictionaryResponse;
}

-(NSMutableDictionary *)parameters
{
    if (_parameters) return _parameters;
    _parameters = [[NSMutableDictionary alloc] init];
    return _parameters;
}


@end
