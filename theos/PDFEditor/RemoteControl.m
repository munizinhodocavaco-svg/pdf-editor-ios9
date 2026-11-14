#import "RemoteControl.h"
#import "Log.h"

@implementation RemoteControl

+ (instancetype)shared {
	static RemoteControl *shared = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shared = [[RemoteControl alloc] init];
	});
	return shared;
}

#pragma mark - Dados da pagina

- (NSData *)pageJPEGWithWidth:(CGFloat)width {
	if (width < 64.0) {
		width = 64.0;
	}
	if (width > 1400.0) {
		width = 1400.0;
	}

	__block UIImage *image = nil;
	if ([NSThread isMainThread]) {
		image = [self.delegate remotePageImageWithWidth:width];
	} else {
		// A renderizacao precisa rodar na thread principal (UIKit).
		dispatch_sync(dispatch_get_main_queue(), ^{
			image = [self.delegate remotePageImageWithWidth:width];
		});
	}

	if (image == nil) {
		return nil;
	}
	return UIImageJPEGRepresentation(image, 0.72);
}

- (NSData *)stateJSON {
	__block NSDictionary *state = nil;
	if ([NSThread isMainThread]) {
		state = [self.delegate remoteState];
	} else {
		dispatch_sync(dispatch_get_main_queue(), ^{
			state = [self.delegate remoteState];
		});
	}
	if (state == nil) {
		state = @{};
	}
	return [NSJSONSerialization dataWithJSONObject:state options:0 error:NULL];
}

#pragma mark - Toques e acoes

- (void)handleTouchX:(double)x y:(double)y phase:(NSInteger)phase {
	if (self.delegate == nil) {
		return;
	}
	CGPoint point = CGPointMake((CGFloat)x, (CGFloat)y);
	if ([NSThread isMainThread]) {
		[self.delegate remoteTouchAtPoint:point phase:phase];
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.delegate remoteTouchAtPoint:point phase:phase];
		});
	}
}

- (BOOL)handleAction:(NSString *)action value:(NSString *)value {
	if (self.delegate == nil || action.length == 0) {
		return NO;
	}
	__block BOOL done = NO;
	if ([NSThread isMainThread]) {
		done = [self.delegate remotePerformAction:action value:value];
	} else {
		dispatch_sync(dispatch_get_main_queue(), ^{
			done = [self.delegate remotePerformAction:action value:value];
		});
	}
	return done;
}

#pragma mark - Pagina de controle

+ (NSString *)controlPageHTML {
	return
	@"<!doctype html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\">"
	"<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover\">"
	"<meta name=\"apple-mobile-web-app-capable\" content=\"yes\">"
	"<title>Leitor / Editor Pdf LM - Remoto</title><style>"
	"*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}"
	"html,body{margin:0;padding:0;height:100%;background:#111;color:#fff;"
	"font-family:-apple-system,Helvetica,Arial,sans-serif;overflow:hidden;"
	"overscroll-behavior:none;touch-action:none}"
	"#top{display:flex;align-items:center;gap:8px;padding:calc(6px + env(safe-area-inset-top)) 10px 6px;"
	"background:#1c1c1e;font-size:13px;font-weight:600}"
	"#top .grow{flex:1;text-align:center;color:#c7c7cc;font-weight:500;overflow:hidden;"
	"text-overflow:ellipsis;white-space:nowrap}"
	"#stage{position:relative;flex:1;display:flex;align-items:center;justify-content:center;"
	"background:#000;overflow:hidden}"
	"/* Sem object-fit: o elemento fica do mesmo tamanho da imagem desenhada, "
	"assim as coordenadas do toque batem exatamente com os pixels. */"
	"#page{max-width:100%;max-height:100%;background:#fff;touch-action:none;"
	"box-shadow:0 0 18px rgba(0,0,0,.6)}"
	"#bar{display:flex;flex-wrap:wrap;gap:6px;padding:8px 8px calc(8px + env(safe-area-inset-bottom));"
	"background:#1c1c1e;justify-content:center}"
	"button{background:#2c2c2e;color:#fff;border:0;border-radius:9px;padding:10px 13px;"
	"font-size:15px;font-weight:600;min-width:44px;min-height:44px;line-height:1.15}"
	"button:active{background:#48484a}"
	"button.on{background:#0a84ff}"
	".sw{width:38px;height:38px;border-radius:19px;border:3px solid #48484a;padding:0}"
	".sw.on{border-color:#0a84ff}"
	"#msg{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);background:rgba(0,0,0,.82);"
	"padding:14px 20px;border-radius:12px;font-size:15px;text-align:center;display:none;max-width:80%}"
	"#live{position:absolute;right:8px;top:8px;background:rgba(0,0,0,.55);border-radius:9px;"
	"padding:5px 9px;font-size:11px;color:#8e8e93;z-index:5}"
	"</style></head><body>"
	"<div id=\"top\"><button onclick=\"act('prev')\">‹</button>"
	"<div class=\"grow\" id=\"info\">conectando…</div>"
	"<button onclick=\"act('next')\">›</button></div>"
	"<div id=\"stage\"><img id=\"page\" alt=\"\"><div id=\"live\">●</div>"
	"<div id=\"msg\"></div></div>"
	"<div id=\"bar\">"
	"<button onclick=\"act('undo')\">↶<br>Desfazer</button>"
	"<button onclick=\"setTool(0)\" id=\"t0\">✏️</button>"
	"<button onclick=\"setTool(1)\" id=\"t1\">🧽</button>"
	"<button onclick=\"setTool(2)\" id=\"t2\">🖍️</button>"
	"<button onclick=\"setSize(1)\" id=\"s1\">1x</button>"
	"<button onclick=\"setSize(2)\" id=\"s2\">2x</button>"
	"<button onclick=\"setSize(3)\" id=\"s3\">3x</button>"
	"<button class=\"sw\" id=\"c0\" style=\"background:#000\" onclick=\"setColor(0)\"></button>"
	"<button class=\"sw\" id=\"c1\" style=\"background:#fff\" onclick=\"setColor(1)\"></button>"
	"<button class=\"sw\" id=\"c2\" style=\"background:#e02626\" onclick=\"setColor(2)\"></button>"
	"<button onclick=\"act('hsv')\">🎨</button>"
	"<button onclick=\"act('save')\">💾<br>Salvar</button>"
	"<button onclick=\"act('replace')\">♻️<br>Original</button>"
	"<button onclick=\"act('refresh')\">🔄</button>"
	"</div><script>"
	"var st={tool:0,size:1,color:0,page:1,pages:1},touching=false,lastSend=0;"
	"var $=function(id){return document.getElementById(id);};"
	"function msg(t){var m=$('msg');m.textContent=t;m.style.display='block';"
	"clearTimeout(m._t);m._t=setTimeout(function(){m.style.display='none';},2500);}"
	"function url(p){return p+'?t='+Date.now();}"
	"function refresh(){if(touching)return;var i=$('page');"
	"var w=Math.min(760,Math.round(window.innerWidth*2));"
	"i.src=url('/remote/view.jpg?w='+w);}"
	"function poll(){fetch(url('/remote/state')).then(function(r){return r.json();})"
	".then(function(d){st=d;var t=d.title?d.title+' · '+d.page+'/'+d.pages:'Pagina '+d.page+' de '+d.pages;"
	"$('info').textContent=t;"
	"$('t0').className=(d.tool==0?'on':'');$('t1').className=(d.tool==1?'on':'');"
	"$('t2').className=(d.tool==2?'on':'');"
	"$('s1').className=(d.size==1?'on':'');$('s2').className=(d.size==2?'on':'');"
	"$('s3').className=(d.size==3?'on':'');"
	"$('c0').className='sw'+((d.color==0)?' on':'');$('c1').className='sw'+((d.color==1)?' on':'');"
	"$('c2').className='sw'+((d.color==2)?' on':'');"
	"}).catch(function(){$('live').style.color='#ff453a';});"
	"setTimeout(poll,1000);}"
	"function act(a,v){fetch(url('/remote/action?a='+encodeURIComponent(a)+'&v='+encodeURIComponent(v||'')))"
	".then(function(r){return r.text();}).then(function(t){if(t&&t!=='ok')msg(t);else if(a=='refresh')refresh();});}"
	"function setTool(t){act('tool',String(t));}"
	"function setSize(s){act('size',String(s));}"
	"function setColor(c){act('color',String(c));}"
	"function pt(e){var r=$('page').getBoundingClientRect();"
	"var t=(e.touches&&e.touches.length)?e.touches[0]:e;"
	"var nw=$('page').naturalWidth||r.width,nh=$('page').naturalHeight||r.height;"
	"return {x:(t.clientX-r.left)*nw/r.width,y:(t.clientY-r.top)*nh/r.height};}"
	"/* Toques limitados a ~25 por segundo: o iPad 2 e lento e o servidor "
	"   atende as requisicoes uma a uma. */"
	"function send(x,y,p){var now=Date.now();"
	"if(p==1&&now-lastSend<40)return;lastSend=now;"
	"fetch(url('/remote/touch?x='+x+'&y='+y+'&p='+p),{method:'POST'}).catch(function(){});}"
	"var im=$('page');"
	"im.addEventListener('touchstart',function(e){e.preventDefault();touching=true;var p=pt(e);send(p.x,p.y,0);},{passive:false});"
	"im.addEventListener('touchmove',function(e){e.preventDefault();if(!touching)return;var p=pt(e);send(p.x,p.y,1);},{passive:false});"
	"im.addEventListener('touchend',function(e){e.preventDefault();touching=false;send(0,0,2);},{passive:false});"
	"im.addEventListener('touchcancel',function(){touching=false;send(0,0,2);});"
	"im.addEventListener('pointerdown',function(e){if(e.pointerType==='touch')return;touching=true;var p=pt(e);send(p.x,p.y,0);});"
	"im.addEventListener('pointermove',function(e){if(e.pointerType==='touch'||!touching)return;var p=pt(e);send(p.x,p.y,1);});"
	"im.addEventListener('pointerup',function(e){if(e.pointerType==='touch')return;touching=false;send(0,0,2);});"
	"im.onload=function(){$('live').style.color='#30d158';};"
	"im.onerror=function(){$('live').style.color='#ff453a';};"
	"refresh();poll();setInterval(refresh,1400);"
	"</script></body></html>";
}

@end
