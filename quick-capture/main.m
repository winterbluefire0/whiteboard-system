#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

@interface BoardCanvas : NSView
@property NSImage *image;
@property NSSize pixels;
@property NSMutableArray<NSValue *> *points;
@property NSTextField *hint;
@property NSButton *confirm;
- (void)resetPoints;
@end
@implementation BoardCanvas
- (BOOL)isFlipped { return YES; }
- (NSRect)imageRect {
    if (!self.image) return NSZeroRect;
    CGFloat scale = MIN(self.bounds.size.width/self.pixels.width,self.bounds.size.height/self.pixels.height);
    NSSize size=NSMakeSize(self.pixels.width*scale,self.pixels.height*scale);
    return NSMakeRect((self.bounds.size.width-size.width)/2,(self.bounds.size.height-size.height)/2,size.width,size.height);
}
- (void)resetPoints {
    self.points=[NSMutableArray new]; self.confirm.enabled=NO;
    self.hint.stringValue=@"依次点击白板内侧四角：左上 → 右上 → 右下 → 左下";
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithWhite:0.13 alpha:1] setFill]; NSRectFill(self.bounds);
    if (!self.image) return;
    NSRect r=[self imageRect];
    [self.image drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    CGFloat scale=r.size.width/self.pixels.width;
    NSBezierPath *path=[NSBezierPath bezierPath];
    for (NSUInteger i=0;i<self.points.count;i++) {
        NSPoint p=self.points[i].pointValue;
        p=NSMakePoint(r.origin.x+p.x*scale,r.origin.y+p.y*scale);
        if (!i) [path moveToPoint:p]; else [path lineToPoint:p];
        [[NSColor systemOrangeColor] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(p.x-6,p.y-6,12,12)] fill];
        [[NSString stringWithFormat:@"%lu",(unsigned long)i+1] drawAtPoint:NSMakePoint(p.x+9,p.y+3) withAttributes:@{NSForegroundColorAttributeName:NSColor.systemOrangeColor,NSFontAttributeName:[NSFont boldSystemFontOfSize:18]}];
    }
    if (self.points.count==4) [path closePath];
    [[NSColor systemOrangeColor] setStroke]; path.lineWidth=2; [path stroke];
}
- (void)mouseDown:(NSEvent *)event {
    if (!self.image || self.points.count>=4) return;
    NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];
    NSRect r=[self imageRect]; if (!NSPointInRect(p,r)) return;
    NSPoint pixel=NSMakePoint((p.x-r.origin.x)*self.pixels.width/r.size.width,(p.y-r.origin.y)*self.pixels.height/r.size.height);
    [self.points addObject:[NSValue valueWithPoint:pixel]];
    self.confirm.enabled=self.points.count==4;
    NSArray *labels=@[@"左上",@"右上",@"右下",@"左下"];
    self.hint.stringValue=self.points.count==4 ? @"确认橙色边框完整包住白板内容，再点“位置确认，开始使用”。" : [NSString stringWithFormat:@"已选 %lu 个角；接下来点 %@",(unsigned long)self.points.count,labels[self.points.count]];
    [self setNeedsDisplay:YES];
}
@end

@interface CaptureApp : NSObject <NSApplicationDelegate>
@property NSString *root;
@property NSStatusItem *status;
@property NSMenuItem *captureItem;
@property NSWindow *window;
@property BoardCanvas *canvas;
@property NSTextField *hint;
@property NSButton *confirm;
@property NSDictionary *preview;
@property NSString *lastImage;
@property NSString *lastError;
@property BOOL busy;
@property BOOL armed;
@property BOOL keysOK;
@property EventHotKeyRef captureKey;
@property EventHotKeyRef prepareKey;
- (void)capture:(id)sender;
- (void)prepare:(id)sender;
@end

static OSStatus hotKeyHandler(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID key; GetEventParameter(event,kEventParamDirectObject,typeEventHotKeyID,NULL,sizeof(key),NULL,&key);
    CaptureApp *app=(__bridge CaptureApp *)context;
    if (key.id==1) [app capture:nil]; else if (key.id==2) [app prepare:nil];
    return noErr;
}
@implementation CaptureApp
- (NSString *)statePath:(NSString *)name { return [self.root stringByAppendingPathComponent:[@"quick-capture/state" stringByAppendingPathComponent:name]]; }
- (void)writeState {
    NSDictionary *d=@{@"running":@YES,@"busy":@(self.busy),@"calibrated_this_launch":@(self.armed),@"hotkeys_registered":@(self.keysOK),@"last_image":self.lastImage?:@"",@"last_error":self.lastError?:@""};
    NSData *data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[self statePath:@"app-status.json"] atomically:YES];
}
- (void)setMessage:(NSString *)message {
    self.status.button.title=self.busy?@"白板…":(self.armed?@"白板 ✓":@"白板");
    self.status.button.toolTip=message;
    self.captureItem.title=message;
    [self writeState];
}
- (NSButton *)button:(NSString *)title x:(CGFloat)x width:(CGFloat)width action:(SEL)action {
    NSButton *b=[NSButton buttonWithTitle:title target:self action:action];
    b.frame=NSMakeRect(x,12,width,32); [self.window.contentView addSubview:b]; return b;
}
- (void)makeWindow {
    if (self.window) return;
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1020,820) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"白板快拍 · 调试位置"; self.window.releasedWhenClosed=NO;
    [self.window center];
    self.hint=[NSTextField labelWithString:@"等待预览照片…"];
    self.hint.frame=NSMakeRect(18,780,990,26); [self.window.contentView addSubview:self.hint];
    self.canvas=[[BoardCanvas alloc] initWithFrame:NSMakeRect(10,54,1000,720)];
    self.canvas.hint=self.hint; [self.window.contentView addSubview:self.canvas];
    [self button:@"重新拍预览" x:16 width:130 action:@selector(prepare:)];
    [self button:@"重选四角" x:157 width:110 action:@selector(reset:)];
    self.confirm=[self button:@"位置确认，开始使用" x:670 width:230 action:@selector(confirmPosition:)];
    self.confirm.enabled=NO; self.canvas.confirm=self.confirm;
    [self button:@"关闭" x:912 width:90 action:@selector(closeWindow:)];
}
- (void)closeWindow:(id)sender { [self.window orderOut:nil]; }
- (void)reset:(id)sender { [self.canvas resetPoints]; }
- (void)fail:(NSString *)reason {
    self.lastError=reason; self.busy=NO; [self setMessage:@"失败：点此重试拍照"];
    NSAlert *alert=[NSAlert new]; alert.messageText=@"白板快拍未完成";
    alert.informativeText=[reason stringByAppendingString:@"\n本次没有复制新图，请勿把旧剪贴板图片当成本次照片。"];
    [NSApp activateIgnoringOtherApps:YES]; [alert runModal];
}
- (void)runPipeline:(NSString *)mode completion:(void (^)(NSDictionary *))completion {
    if (self.busy) { NSBeep(); return; }
    self.busy=YES; self.lastError=nil; [self setMessage:@"正在拍照并处理…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSTask *task=[NSTask new];
        task.executableURL=[NSURL fileURLWithPath:[self.root stringByAppendingPathComponent:@".tools/venv/bin/python"]];
        task.arguments=@[[self.root stringByAppendingPathComponent:@"quick-capture/pipeline.py"],mode];
        task.currentDirectoryURL=[NSURL fileURLWithPath:self.root];
        NSPipe *pipe=[NSPipe pipe]; task.standardOutput=pipe; task.standardError=pipe;
        NSError *error=nil; BOOL ok=[task launchAndReturnError:&error];
        NSData *data=ok?[pipe.fileHandleForReading readDataToEndOfFile]:nil;
        if (ok) [task waitUntilExit];
        NSDictionary *result=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        NSString *message=error.localizedDescription ?: result[@"error"];
        if (!message && (!ok || task.terminationStatus || !result)) message=[[NSString alloc] initWithData:data?:[NSData data] encoding:NSUTF8StringEncoding]?:@"无法读取拍照结果。";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy=NO;
            if (message) { [self fail:message]; return; }
            completion(result);
        });
    });
}
- (void)prepare:(id)sender {
    if (self.busy) return;
    self.armed=NO; [self makeWindow]; [self.canvas resetPoints];
    self.hint.stringValue=@"正在拍预览。调整机位后，可以再次点“重新拍预览”。";
    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [self runPipeline:@"preview" completion:^(NSDictionary *result) {
        self.preview=result;
        self.canvas.image=[[NSImage alloc] initWithContentsOfFile:result[@"original"]];
        self.canvas.pixels=NSMakeSize([result[@"width"] doubleValue],[result[@"height"] doubleValue]);
        [self.canvas resetPoints]; [self setMessage:@"请先确认白板四角"];
    }];
}
- (void)confirmPosition:(id)sender {
    if (self.busy || self.canvas.points.count!=4) return;
    NSMutableArray *corners=[NSMutableArray new];
    double area=0; int sign=0;
    for (int i=0;i<4;i++) {
        NSPoint a=self.canvas.points[i].pointValue,b=self.canvas.points[(i+1)%4].pointValue,c=self.canvas.points[(i+2)%4].pointValue;
        double cross=(b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x);
        if (cross<=0) { [self fail:@"四角顺序不正确，请按左上、右上、右下、左下重选。"]; return; }
        area+=a.x*b.y-b.x*a.y; sign++;
        [corners addObject:@[@(a.x),@(a.y)]];
    }
    if (sign!=4 || area/2<self.canvas.pixels.width*self.canvas.pixels.height*0.1) { [self fail:@"选区太小，请覆盖完整白板。"]; return; }
    NSDictionary *config=@{@"id":NSUUID.UUID.UUIDString,@"corners":corners,@"image_size":@[@(self.canvas.pixels.width),@(self.canvas.pixels.height)],@"reference_image":self.preview[@"original"],@"confirmed_at":[[NSISO8601DateFormatter new] stringFromDate:NSDate.date]};
    NSData *data=[NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:nil];
    if (![data writeToFile:[self statePath:@"calibration.json"] atomically:YES]) { [self fail:@"无法保存位置标定。"]; return; }
    self.lastError=nil; self.armed=YES; [self setMessage:@"拍照并复制彩色图 · ⌃⌥⌘B"];
    [self.window orderOut:nil];
}
- (BOOL)copyImage:(NSString *)path {
    NSData *png=[NSData dataWithContentsOfFile:path];
    NSImage *image=[[NSImage alloc] initWithData:png];
    if (!png || !image) return NO;
    NSPasteboardItem *item=[NSPasteboardItem new];
    [item setData:png forType:NSPasteboardTypePNG];
    NSData *tiff=image.TIFFRepresentation;
    if (tiff) [item setData:tiff forType:NSPasteboardTypeTIFF];
    NSPasteboard *pb=NSPasteboard.generalPasteboard;
    [pb clearContents];
    return [pb writeObjects:@[item]] && [[pb dataForType:NSPasteboardTypePNG] isEqualToData:png];
}
- (void)capture:(id)sender {
    if (self.busy) return;
    if (!self.armed) { [self prepare:nil]; return; }
    [self runPipeline:@"capture" completion:^(NSDictionary *result) {
        self.lastImage=result[@"color"];
        if (![self copyImage:self.lastImage]) { [self fail:@"图片已保存，但复制到剪贴板失败，可从图片文件夹拖入聊天。"]; return; }
        [self setMessage:@"已复制新图，回到聊天按 ⌘V · 再拍 ⌃⌥⌘B"];
        [[NSSound soundNamed:@"Glass"] play];
    }];
}
- (void)recopy:(id)sender {
    if (!self.lastImage) { NSBeep(); return; }
    if (![self copyImage:self.lastImage]) [self fail:@"未能复制最近照片。"];
    else [self setMessage:@"已重新复制最近照片，按 ⌘V 粘贴"];
}
- (void)showFiles:(id)sender {
    NSURL *url=[NSURL fileURLWithPath:self.lastImage?:[self.root stringByAppendingPathComponent:@"captures"]];
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[url]];
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)note {
    if(self.captureKey) UnregisterEventHotKey(self.captureKey);
    if(self.prepareKey) UnregisterEventHotKey(self.prepareKey);
    [@"{\"running\":false}" writeToFile:[self statePath:@"app-status.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.root=[[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"workspace" ofType:@"txt"] encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!self.root.length) { [NSApp terminate:nil]; return; }
    [NSFileManager.defaultManager createDirectoryAtPath:[self statePath:@""] withIntermediateDirectories:YES attributes:nil error:nil];
    self.status=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSMenu *menu=[NSMenu new];
    self.captureItem=[[NSMenuItem alloc] initWithTitle:@"拍照并复制彩色图 · ⌃⌥⌘B" action:@selector(capture:) keyEquivalent:@""];
    self.captureItem.target=self; [menu addItem:self.captureItem];
    NSArray *titles=@[@"调试位置 / 新一轮使用 · ⌃⌥⌘P",@"重新复制最近彩色图",@"打开照片位置",@"退出白板快拍"];
    SEL actions[]={@selector(prepare:),@selector(recopy:),@selector(showFiles:),@selector(quit:)};
    for(int i=0;i<4;i++){NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:titles[i] action:actions[i] keyEquivalent:@""];item.target=self;[menu addItem:item];}
    self.status.menu=menu;
    EventTypeSpec type={kEventClassKeyboard,kEventHotKeyPressed};
    InstallApplicationEventHandler(hotKeyHandler,1,&type,(__bridge void *)self,NULL);
    EventHotKeyID a={'WBCP',1},b={'WBCP',2};
    OSStatus sa=RegisterEventHotKey(kVK_ANSI_B,controlKey|optionKey|cmdKey,a,GetApplicationEventTarget(),0,&_captureKey);
    OSStatus sb=RegisterEventHotKey(kVK_ANSI_P,controlKey|optionKey|cmdKey,b,GetApplicationEventTarget(),0,&_prepareKey);
    self.keysOK=sa==noErr && sb==noErr;
    [self setMessage:@"请先调试位置 · ⌃⌥⌘P"];
    if (!self.keysOK) [self fail:@"快捷键可能被占用，请先用菜单栏“白板”的拍照/调试按钮。"];
    // Opening the utility shows readiness, but does not automatically take a photo.
}
@end
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        CaptureApp *delegate=[CaptureApp new]; app.delegate=delegate; [app run];
    }
    return 0;
}
