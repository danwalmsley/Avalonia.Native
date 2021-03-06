#include "common.h"

class WindowBaseImpl;

@interface AvnView : NSView
-(AvnView*)  initWithParent: (WindowBaseImpl*) parent;
@end

@interface AvnWindow : NSWindow <NSWindowDelegate>
-(AvnWindow*) initWithParent: (WindowBaseImpl*) parent;
-(void) setCanBecomeKeyAndMain;
@end




class WindowBaseImpl : public ComSingleObject<IAvnWindowBase, &IID_IAvnWindowBase>
{
public:
    AvnView* View;
    AvnWindow* Window;
    ComPtr<IAvnWindowBaseEvents> BaseEvents;
    WindowBaseImpl(IAvnWindowBaseEvents* events)
    {
        BaseEvents = events;
        View = [[AvnView alloc] initWithParent:this];
        Window = [[AvnWindow alloc] initWithParent:this];
        [Window setStyleMask:NSWindowStyleMaskBorderless];
        [Window setBackingType:NSBackingStoreBuffered];
        [Window setContentView: View];
    }
    
    virtual HRESULT Show()
    {
        [Window makeKeyAndOrderFront:Window];
        return S_OK;
    }
    
    virtual HRESULT Close()
    {
        [Window close];
        return S_OK;
    }
    
    virtual HRESULT GetClientSize(AvnSize* ret)
    {
        if(ret == nullptr)
            return E_POINTER;
        auto frame = [View frame];
        ret->Width = frame.size.width;
        ret->Height = frame.size.height;
        return S_OK;
    }
    
    virtual HRESULT Resize(double x, double y)
    {
        [Window setContentSize:NSSize{x, y}];
        return S_OK;
    }
    
protected:
    virtual NSWindowStyleMask GetStyle()
    {
        return NSWindowStyleMaskBorderless;
    }
    
    void UpdateStyle()
    {
        [Window setStyleMask:GetStyle()];
    }
    
    
};


@implementation AvnView
{
    ComPtr<WindowBaseImpl> _parent;
}

-(AvnView*)  initWithParent: (WindowBaseImpl*) parent
{
    self = [super init];
    _parent = parent;
    return self;
}

- (BOOL)isOpaque
{
    return true;
}

-(void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    _parent->BaseEvents->Resized(AvnSize{newSize.width, newSize.height});
}

- (void)drawRect:(NSRect)dirtyRect
{
    auto logicalSize = [self frame].size;
    auto pixelSize = [self convertSizeToBacking:logicalSize];
    int w = pixelSize.width;
    int h = pixelSize.height;
    int stride = w * 4;
    void*ptr = malloc(h * stride);
    _parent->BaseEvents->SoftwareDraw(ptr, stride, w, h, AvnSize{logicalSize.width, logicalSize.height});
    
    auto colorSpace = CGColorSpaceCreateDeviceRGB();
    auto bctx = CGBitmapContextCreate(ptr, w, h, 8, stride, colorSpace, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    auto image = CGBitmapContextCreateImage(bctx);
    CGContextRelease(bctx);
    CGColorSpaceRelease(colorSpace);
    
    auto ctx = [NSGraphicsContext currentContext];
    
    [ctx saveGraphicsState];
    auto cgc = [ctx CGContext];
    
    CGContextDrawImage(cgc, CGRect{0,0, logicalSize.width, logicalSize.height}, image);
    CGImageRelease(image);
    
    [ctx restoreGraphicsState];
    free(ptr);
}
@end


@implementation AvnWindow
{
    ComPtr<WindowBaseImpl> _parent;
    bool _canBecomeKeyAndMain;
}

-(void) setCanBecomeKeyAndMain
{
    _canBecomeKeyAndMain = true;
}

-(AvnWindow*)  initWithParent: (WindowBaseImpl*) parent
{
    self = [super init];
    _parent = parent;
    [self setDelegate:self];
    return self;
}

-(BOOL)canBecomeKeyWindow
{
    return _canBecomeKeyAndMain;
}

-(BOOL)canBecomeMainWindow
{
    return _canBecomeKeyAndMain;
}

-(void)becomeKeyWindow
{
    [super becomeKeyWindow];
    _parent->BaseEvents->Activated();
}

-(void)resignKeyWindow
{
    _parent->BaseEvents->Deactivated();
    [super resignKeyWindow];
}

@end


class WindowImpl : public WindowBaseImpl, public IAvnWindow
{
private:
    bool _canResize = true;
    bool _hasDecorations = true;
    
    BEGIN_INTERFACE_MAP()
    INHERIT_INTERFACE_MAP(WindowBaseImpl)
    INTERFACE_MAP_ENTRY(IAvnWindow, IID_IAvnWindow)
    END_INTERFACE_MAP()
    ComPtr<IAvnWindowEvents> WindowEvents;
    WindowImpl(IAvnWindowEvents* events) : WindowBaseImpl(events)
    {
        WindowEvents = events;
        [Window setCanBecomeKeyAndMain];
        UpdateStyle();
    }
    
    
    virtual HRESULT SetCanResize(bool value)
    {
        _canResize = value;
        UpdateStyle();
        return S_OK;
    }
    
    virtual HRESULT SetHasDecorations(bool value)
    {
        _hasDecorations = value;
        UpdateStyle();
        return S_OK;
    }
    
protected:
    virtual NSWindowStyleMask GetStyle()
    {
        unsigned long s = NSWindowStyleMaskBorderless;
        if(_hasDecorations)
            s = s | NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
        if(_canResize)
            s = s | NSWindowStyleMaskResizable;
        return s;
    }
};


extern IAvnWindow* CreateAvnWindow(IAvnWindowEvents*events)
{
    IAvnWindow* ptr = dynamic_cast<IAvnWindow*>(new WindowImpl(events));
    return ptr;
}
