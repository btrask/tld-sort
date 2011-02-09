/* Copyright (c) 2011, Ben Trask
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * The names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY BEN TRASK ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL BEN TRASK BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import <Foundation/Foundation.h>

enum {
	BTDomainRankFieldIndex,
	BTDomainNameFieldIndex,
	BTFieldCount,
};

NSArray *BTFlagsWithArguments(NSArray *arguments);
NSArray *BTFieldsByLineInCSVString(NSString *csvString, BOOL verbose);
NSString *BTDomainNameWithoutPath(NSString *domainName);
NSString *BTTLDWithDomainName(NSString *domainName);

@interface NSString(BTAdditions)
- (NSString *)BT_stringByStandardizingPathWithCurrentWorkingDirectory;
@end

int main(int argc, char const *argv[])
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	NSArray *const args = [[NSProcessInfo processInfo] arguments];
	NSString *const csvPathArgument = [args lastObject];
	if([args count] < 2 || '-' == [csvPathArgument characterAtIndex:0]) {
		printf("Usage: tld-sort [options] csv-file\n");
		printf("\t-q --quiet\tHide progress and stats\n");
		printf("\t-c --count\tPrint raw numbers instead of percents\n");
		printf("\t-d --domains\tPrint full domains instead of numbers (slow)\n");
		printf("\t-t --top\tOnly print the top few domains for each TLD (implies -d)\n");
		return EXIT_SUCCESS;
	}

	NSArray *const flags = BTFlagsWithArguments(args);
	BOOL verbose = YES;
	BOOL showPercent = YES;
	BOOL showDomains = NO;
	BOOL showTopOnly = NO;
	if([flags containsObject:@"q"] || [flags containsObject:@"quiet"]) verbose = NO;
	if([flags containsObject:@"c"] || [flags containsObject:@"count"]) showPercent = NO;
	if([flags containsObject:@"d"] || [flags containsObject:@"domains"]) showDomains = YES;
	if([flags containsObject:@"t"] || [flags containsObject:@"top"]) showTopOnly = showDomains = YES;

	NSError *csvError = nil;
	NSString *const csvString = [NSString stringWithContentsOfFile:[csvPathArgument BT_stringByStandardizingPathWithCurrentWorkingDirectory] encoding:NSUTF8StringEncoding error:&csvError];
	if(!csvString) {
		if(csvError) fprintf(stderr, "Error: %s\n", [[csvError localizedDescription] UTF8String]);
		[pool drain];
		return EXIT_FAILURE;
	}
	NSArray *const lines = BTFieldsByLineInCSVString(csvString, verbose);

	NSUInteger domainCount = 0;

	NSMutableArray *const TLDs = [NSMutableArray array];
	NSMutableDictionary *const domainsByTLD = [NSMutableDictionary dictionary];
	for(NSArray *const line in lines) {
		if([line count] < BTFieldCount) continue;
		NSString *const domainName = BTDomainNameWithoutPath([line objectAtIndex:BTDomainNameFieldIndex]);
		NSString *const TLD = BTTLDWithDomainName(domainName);
		if(!TLD) continue;
		NSMutableArray *domains = [domainsByTLD objectForKey:TLD];
		if(!domains) {
			domains = [NSMutableArray array];
			[domainsByTLD setObject:domains forKey:TLD];
			[TLDs addObject:TLD];
		}
		[domains addObject:domainName];
		++domainCount;
	}

	CGFloat otherPercent = 0.0;
	for(NSString *const TLD in TLDs) {
		NSArray *const domains = [domainsByTLD objectForKey:TLD];
		NSUInteger const count = [domains count];
		if(showDomains) {
			NSUInteger i = 0;
			NSUInteger const max = showTopOnly ? (NSUInteger)round(((double)count / domainCount) * 100.0) : count;
			if(max) printf(".%s:\n", [TLD UTF8String]);
			for(; i < max; ++i) printf("\t%s\n", [[domains objectAtIndex:i] UTF8String]);
		} else {
			if(showPercent) {
				CGFloat const percent = ((CGFloat)count / domainCount) * 100.0;
				if(percent > 0.25) printf(".%s: %.2f%%\n", [TLD UTF8String], (double)percent);
				else otherPercent += percent;
			} else printf(".%s: %lu\n", [TLD UTF8String], (unsigned long)count);
		}
	}
	if(showPercent && !showDomains) printf("Other: %.2f%%\n", (double)otherPercent);
	if(verbose) {
		NSUInteger const TLDCount = [TLDs count];
		printf("%lu domains in %lu TLDs\n", (unsigned long)domainCount, (unsigned long)TLDCount);
		if(TLDCount) {
			NSString *const firstTLD = [TLDs objectAtIndex:0];
			NSUInteger const firstTLDCount = [[domainsByTLD objectForKey:firstTLD] count];
			printf("%lu .%s domains count for %.2f%% of total\n", firstTLDCount, [firstTLD UTF8String], ((double)firstTLDCount / domainCount) * 100.0);
		}
	}

	[pool drain];
	return EXIT_SUCCESS;
}

NSArray *BTFlagsWithArguments(NSArray *arguments)
{
	NSMutableArray *const flags = [NSMutableArray array];
	for(NSString *const arg in arguments) if('-' == [arg characterAtIndex:0]) {
		if('-' == [arg characterAtIndex:1]) {
			[flags addObject:[arg substringFromIndex:2]];
		} else {
			NSUInteger i = 0;
			NSUInteger const length = [arg length];
			for(; i < length; ++i) [flags addObject:[arg substringWithRange:NSMakeRange(i, 1)]];
		}
	}
	return flags;
}
NSArray *BTFieldsByLineInCSVString(NSString *csvString, BOOL verbose)
{
	NSCharacterSet *const fieldSeparators = [NSCharacterSet characterSetWithCharactersInString:@","];
	NSCharacterSet *const lineSeparators = [NSCharacterSet characterSetWithCharactersInString:@"\n\r"];
	NSCharacterSet *const allSeparators = [NSCharacterSet characterSetWithCharactersInString:@"\n\r,"];

	NSUInteger counter = 0;
	NSUInteger const length = [csvString length];
	NSScanner *const scanner = [NSScanner scannerWithString:csvString];
	[scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@""]];

	NSMutableArray *const results = [NSMutableArray arrayWithObjects:[NSMutableArray array], nil];
	while(![scanner isAtEnd]) {
		NSAutoreleasePool *const pool = [[NSAutoreleasePool alloc] init];
		NSString *field = nil;
		if([scanner scanCharactersFromSet:lineSeparators intoString:NULL]) [results addObject:[NSMutableArray array]];
		if([scanner scanUpToCharactersFromSet:allSeparators intoString:&field]) [[results lastObject] addObject:field];
		[scanner scanCharactersFromSet:fieldSeparators intoString:NULL];
		if(verbose && !(++counter % 400000)) {
			printf("Scanning: %lu%%\n", (unsigned long)round(((double)[scanner scanLocation] / length) * 100.0));
		}
		[pool drain];
	}
	if(verbose) printf("Scanned %lu lines\n", (unsigned long)[results count]);
	return results;
}
NSString *BTDomainNameWithoutPath(NSString *domainName)
{
	NSUInteger const pathIndex = [domainName rangeOfString:@"/" options:NSLiteralSearch].location;
	if(NSNotFound == pathIndex) return domainName;
	return [domainName substringToIndex:pathIndex];
}
NSString *BTTLDWithDomainName(NSString *domainName)
{
	NSUInteger const TLDIndex = [domainName rangeOfString:@"." options:NSBackwardsSearch | NSLiteralSearch].location;
	if(NSNotFound == TLDIndex) return nil;
	NSString *const TLD = [domainName substringFromIndex:TLDIndex + 1];
	if(NSNotFound == [TLD rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet] options:NSLiteralSearch].location) return nil;
	return [TLD lowercaseString];
}

@implementation NSString(BTAdditions)
- (NSString *)BT_stringByStandardizingPathWithCurrentWorkingDirectory {
	if([self isAbsolutePath]) return [self stringByStandardizingPath];
	char *const cwd = getcwd(NULL, SIZE_MAX);
	NSString *const workingDirectory = [[[NSString alloc] initWithBytesNoCopy:cwd length:strlen(cwd) encoding:NSUTF8StringEncoding freeWhenDone:YES] autorelease];
	return [[workingDirectory stringByAppendingPathComponent:self] stringByStandardizingPath];
}
@end
