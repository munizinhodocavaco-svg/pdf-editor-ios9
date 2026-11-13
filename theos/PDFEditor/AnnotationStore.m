#import "AnnotationStore.h"

@interface AnnotationStore ()
@property (nonatomic, strong, readwrite) NSURL *pdfURL;
@property (nonatomic, strong) NSMutableDictionary *pages;
@end

@implementation AnnotationStore

- (instancetype)initWithPDFURL:(NSURL *)pdfURL {
	self = [super init];
	if (self) {
		_pdfURL = pdfURL;
		_pages = [NSMutableDictionary dictionary];
		[self load];
	}
	return self;
}

- (NSString *)annotationsPath {
	return [self.pdfURL.path stringByAppendingString:@".annotations.json"];
}

- (NSMutableArray *)mutableAnnotationsForPage:(NSUInteger)page {
	NSNumber *key = @(page);
	NSMutableArray *array = [self.pages objectForKey:key];
	if (array == nil) {
		array = [NSMutableArray array];
		[self.pages setObject:array forKey:key];
	}
	return array;
}

- (NSArray *)annotationsForPage:(NSUInteger)page {
	NSMutableArray *array = [self.pages objectForKey:@(page)];
	if (array == nil) {
		return @[];
	}
	return [array copy];
}

- (void)addAnnotation:(Annotation *)annotation toPage:(NSUInteger)page {
	if (annotation == nil) {
		return;
	}
	[[self mutableAnnotationsForPage:page] addObject:annotation];
	[self save];
}

- (void)removeAnnotation:(Annotation *)annotation fromPage:(NSUInteger)page {
	if (annotation == nil) {
		return;
	}
	[[self mutableAnnotationsForPage:page] removeObjectIdenticalTo:annotation];
	[self save];
}

- (void)save {
	NSMutableDictionary *serialized = [NSMutableDictionary dictionary];
	for (NSNumber *key in self.pages) {
		NSArray *annotations = [self.pages objectForKey:key];
		NSMutableArray *list = [NSMutableArray array];
		for (Annotation *annotation in annotations) {
			[list addObject:[annotation dictionaryRepresentation]];
		}
		[serialized setObject:list forKey:[key stringValue]];
	}

	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:serialized options:0 error:&error];
	if (data != nil) {
		[data writeToFile:[self annotationsPath] atomically:YES];
	}
}

- (void)load {
	[self.pages removeAllObjects];
	NSData *data = [NSData dataWithContentsOfFile:[self annotationsPath]];
	if (data == nil) {
		return;
	}
	NSError *error = nil;
	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (![json isKindOfClass:[NSDictionary class]]) {
		return;
	}
	for (NSString *key in json) {
		NSArray *list = [json objectForKey:key];
		if (![list isKindOfClass:[NSArray class]]) {
			continue;
		}
		NSMutableArray *annotations = [NSMutableArray array];
		for (NSDictionary *dictionary in list) {
			if ([dictionary isKindOfClass:[NSDictionary class]]) {
				[annotations addObject:[Annotation annotationFromDictionary:dictionary]];
			}
		}
		[self.pages setObject:annotations forKey:@([key integerValue])];
	}
}

@end
