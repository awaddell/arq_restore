/*
 Copyright (c) 2009-2011, Stefan Reitshamer http://www.haystacksoftware.com
 
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 * Neither the names of PhotoMinds LLC or Haystack Software, nor the names of 
 their contributors may be used to endorse or promote products derived from
 this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */ 

#import "S3AuthorizationProvider.h"
#import "LocalS3Signer.h"
#import "HTTPConnection.h"

/*
 * WARNING: 
 * This class *must* be reentrant!
 */

@interface S3AuthorizationProvider (internal)
- (NSString *)authorizationForString:(NSString *)stringToSign error:(NSError **)error;
- (NSString *)stringToSignForS3BucketName:(NSString *)theS3BucketName connection:(id <HTTPConnection>)theConnection;
@end

@implementation S3AuthorizationProvider
- (id)initWithAccessKey:(NSString *)access secretKey:(NSString *)secret {
	if (self = [super init]) {
        NSAssert(access != nil, @"access key can't be nil");
        NSAssert(secret != nil, @"secret key can't be nil");
		accessKey = [access copy];
        signer = [[LocalS3Signer alloc] initWithSecretKey:secret];
	}
	return self;
}
- (void)dealloc {
	[accessKey release];
	[signer release];
	[super dealloc];
}
- (NSString *)accessKey {
	return accessKey;
}
- (BOOL)setAuthorizationRequestHeaderOnHTTPConnection:(id <HTTPConnection>)conn usingS3BucketName:(NSString *)s3BucketName error:(NSError **)error {
    NSString *stringToSign = [self stringToSignForS3BucketName:s3BucketName connection:conn];
    NSString *authorization = [self authorizationForString:stringToSign error:error];
    if (authorization == nil) {
        return NO;
    }
    [conn setRequestHeader:authorization forKey:@"Authorization"];
    return YES;
}
@end

@implementation S3AuthorizationProvider (internal)
- (NSString *)authorizationForString:(NSString *)stringToSign error:(NSError **)error {
    NSString *signature = [signer sign:stringToSign error:error];
    if (signature == nil) {
        return nil;
    }
	NSMutableString *buf = [[[NSMutableString alloc] init] autorelease];
	[buf appendString:@"AWS "];
	[buf appendString:accessKey];
	[buf appendString:@":"];
	[buf appendString:signature];
	NSString *ret = [NSString stringWithString:buf];
	if ([ret hasSuffix:@"\n"]) {
		NSUInteger length = [ret length];
		ret = [ret substringToIndex:(length - 1)];
	}
	return ret;
}
- (NSString *)stringToSignForS3BucketName:(NSString *)theS3BucketName connection:(id <HTTPConnection>)theConnection {
    NSMutableString *buf = [[[NSMutableString alloc] init] autorelease];
	[buf appendString:[theConnection requestMethod]];
	[buf appendString:@"\n"];
    NSString *contentMd5 = [theConnection requestHeaderForKey:@"Content-Md5"];
    if (contentMd5 != nil) {
        [buf appendString:contentMd5];
    }
    [buf appendString:@"\n"];
    NSString *contentType = [theConnection requestHeaderForKey:@"Content-Type"];
    if (contentType != nil) {
        [buf appendString:contentType];
    }
	[buf appendString:@"\n"];
	[buf appendString:[theConnection requestHeaderForKey:@"Date"]];
	[buf appendString:@"\n"];
    NSMutableArray *xamzHeaders = [NSMutableArray array];
    for (NSString *headerName in [theConnection requestHeaderKeys]) {
        NSString *lower = [headerName lowercaseString];
        if ([lower hasPrefix:@"x-amz-"]) {
            [xamzHeaders addObject:[NSString stringWithFormat:@"%@:%@\n", lower, [theConnection requestHeaderForKey:headerName]]];
        }
    }
    [xamzHeaders sortUsingSelector:@selector(compare:)];
    for (NSString *xamz in xamzHeaders) {
        [buf appendString:xamz];
    }
	if ([theS3BucketName length] > 0) {
		[buf appendString:@"/"];
		[buf appendString:theS3BucketName];
	}
	[buf appendString:[theConnection requestPathInfo]];
    NSString *queryString = [theConnection requestQueryString];
    if ([queryString isEqualToString:@"?acl"]
        || [queryString isEqualToString:@"?logging"] 
        || [queryString isEqualToString:@"?torrent"] 
        || [queryString isEqualToString:@"?location"]) {
        [buf appendString:queryString];
    }
#if 0
    {
        HSLogDebug(@"string to sign: <%@>", buf);
        const char *stringToSignBytes = [buf UTF8String];
        int stringToSignLen = strlen(stringToSignBytes);
        NSMutableString *displayBytes = [[[NSMutableString alloc] init] autorelease];
        for (int i = 0; i < stringToSignLen; i++) {
            [displayBytes appendString:[NSString stringWithFormat:@"%02x ", stringToSignBytes[i]]];
        }
        HSLogDebug(@"string to sign bytes: <%@>", displayBytes);
    }
#endif
    return buf;
}
@end
