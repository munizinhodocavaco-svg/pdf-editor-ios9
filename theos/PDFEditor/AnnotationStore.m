#import "AnnotationStore.h"

@interface AnnotationStore ()
@property (nonatomic, strong, readwrite) NSURL *pdfURL;
@property (nonatomic, strong) NSMutableDictionary *pages;
/* Contador de geracao: cada alteracao incrementa; o timer de gravacao so
   grava se nenhuma alteracao nova aconteceu depois que ele foi agendado. */
@property (nonatomic, assign) NSInteger saveGeneration;
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

/* Gravacao em segundo plano: evita travar a tela quando o arquivo de anotacoes
   fica grande. O retrato e tirado na thread principal (rapido) e o JSON e
   montado/escrito numa fila serial.

   MODO ECONOMIA: como cada traco chamava save(), o iPad 2 ficava gravando
   o JSON o tempo todo (gasto de energia + travadas). Agora as gravacoes sao
   agrupadas: varias alteracoes seguidas viram UMA gravacao 1,5 s depois.
   O flushNow e usado quando o app vai para segundo plano, garantindo que
   nada se perca. */
- (void)save {
	NSInteger generation = self.saveGeneration + 1;
	self.saveGeneration = generation;

	__weak AnnotationStore *weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		AnnotationStore *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		// Houve alteracoes depois desta: o timer mais recente assume.
		if (strongSelf.saveGeneration != generation) {
			return;
		}
		[strongSelf flushNow];
	});
}

/* Grava imediatamente (usado no background do app e ao sair da tela). */
- (void)flushNow {
	NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
	for (NSNumber *key in self.pages) {
		NSArray *annotations = [self.pages objectForKey:key];
		[snapshot setObject:[annotations copy] forKey:key];
	}
	NSString *path = [self annotationsPath];

	static dispatch_queue_t queue = NULL;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("com.lucaspdf.editor.annotacoes", DISPATCH_QUEUE_SERIAL);
	});

	dispatch_async(queue, ^{
		NSMutableDictionary *serialized = [NSMutableDictionary dictionary];
		for (NSNumber *key in snapshot) {
			NSArray *annotations = [snapshot objectForKey:key];
			NSMutableArray *list = [NSMutableArray arrayWithCapacity:annotations.count];
			for (Annotation *annotation in annotations) {
				[list addObject:[annotation dictionaryRepresentation]];
			}
			[serialized setObject:list forKey:[key stringValue]];
		}

		NSData *data = [NSJSONSerialization dataWithJSONObject:serialized options:0 error:NULL];
		if (data != nil) {
			[data writeToFile:path atomically:YES];
		}
	});
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
