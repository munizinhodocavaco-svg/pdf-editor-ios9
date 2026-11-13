#import <Foundation/Foundation.h>

/* Log de diagnostico: grava em Documents/launch.log (ou /tmp se nao houver sandbox). */
void PDFLog(NSString *format, ...);

/* Instala handlers de excecao e de sinais para registrar travamentos. */
void PDFInstallCrashHandlers(void);
