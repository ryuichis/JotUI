//
//  FilledPathElement.m
//  JotUI
//
//  Created by Adam Wulf on 2/5/14.
//  Copyright (c) 2014 Adonit. All rights reserved.
//

#import "FilledPathElement.h"
#import "AbstractBezierPathElement-Protected.h"
#import <MessageUI/MFMailComposeViewController.h>

@implementation FilledPathElement{
    // cache the hash, since it's expenseive to calculate
    NSUInteger hashCache;
    // bezier path
    UIBezierPath* path;
    // create texture
    JotGLTexture* texture;
    //
    CGPoint p1;
    CGPoint p2;
    CGPoint p3;
    CGPoint p4;
    
    CGFloat scaleToDraw;
    CGAffineTransform scaleTransform;
}

-(UIColor*) color{
    return [UIColor blackColor];
}


-(id) initWithPath:(UIBezierPath*)_path andP1:(CGPoint)_p1 andP2:(CGPoint)_p2 andP3:(CGPoint)_p3 andP4:(CGPoint)_p4{
    if(self = [super initWithStart:CGPointZero]){
        path = [_path copy];
        
        p1 = _p1;
        p2 = _p2;
        p3 = _p3;
        p4 = _p4;
        
        NSUInteger prime = 31;
        hashCache = 1;
        hashCache = prime * hashCache + p1.x;
        hashCache = prime * hashCache + p1.y;
        hashCache = prime * hashCache + p2.x;
        hashCache = prime * hashCache + p2.y;
        hashCache = prime * hashCache + p3.x;
        hashCache = prime * hashCache + p3.y;
        hashCache = prime * hashCache + p4.x;
        hashCache = prime * hashCache + p4.y;
        
        [self generateTextureFromPath];
        
        scaleToDraw = 1.0;
        scaleTransform = CGAffineTransformIdentity;
    }
    return self;
}

+(id) elementWithPath:(UIBezierPath*)path andP1:(CGPoint)_p1 andP2:(CGPoint)_p2 andP3:(CGPoint)_p3 andP4:(CGPoint)_p4{
    return [[FilledPathElement alloc] initWithPath:path andP1:_p1 andP2:_p2 andP3:_p3 andP4:_p4];
}


-(void) generateTextureFromPath{
    [path applyTransform:CGAffineTransformMakeTranslation(-path.bounds.origin.x, -path.bounds.origin.y)];
    CGRect textureBounds = CGRectMake(0, 0, ceilf(path.bounds.size.width), ceilf(path.bounds.size.height));
    
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext = CGBitmapContextCreate(NULL, textureBounds.size.width, textureBounds.size.height, 8, textureBounds.size.width * 4, colorspace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast);
    if(!bitmapContext){
        @throw [NSException exceptionWithName:@"CGContext Exception" reason:@"can't create new context" userInfo:nil];
    }
    UIGraphicsPushContext(bitmapContext);
    
    CGContextClearRect(bitmapContext, CGRectMake(0, 0, textureBounds.size.width, textureBounds.size.height));
    
    // flip vertical for our drawn content, since OpenGL is opposite core graphics
    CGContextTranslateCTM(bitmapContext, 0, path.bounds.size.height);
    CGContextScaleCTM(bitmapContext, 1.0, -1.0);
    
    //
    // ok, now render our actual content
    CGContextClearRect(bitmapContext, CGRectMake(0.0, 0.0, textureBounds.size.width, textureBounds.size.height));
    [[UIColor whiteColor] setFill];
    [path fill];
    
    // Retrieve the UIImage from the current context
    CGImageRef cgImage = CGBitmapContextCreateImage(bitmapContext);
    if(!cgImage){
        @throw [NSException exceptionWithName:@"CGContext Exception" reason:@"can't create new context" userInfo:nil];
    }
    
    UIImage* image = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
    
    // Clean up
    CFRelease(colorspace);
    UIGraphicsPopContext();
    CGContextRelease(bitmapContext);
    
    // ok, we're done exporting and cleaning up
    // so pass the newly generated image to the completion block
    texture = [[JotGLTexture alloc] initForImage:image withSize:image.size];
    CGImageRelease(cgImage);
}

/**
 * the length along the curve of this element.
 * since it's a curve, this will be longer than
 * the straight distance between start/end points
 */
-(CGFloat) lengthOfElement{
    return 0;
}

-(CGRect) bounds{
    return [path bounds];
}


-(NSInteger) numberOfBytesGivenPreviousElement:(AbstractBezierPathElement*)previousElement{
    // find out how many steps we can put inside this segment length
    return 0;
}

/**
 * generate a vertex buffer array for all of the points
 * along this curve for the input scale.
 *
 * this method will cache the array for a single scale. if
 * a new scale is sent in later, then the cache will be rebuilt
 * for the new scale.
 */
-(struct ColorfulVertex*) generatedVertexArrayWithPreviousElement:(AbstractBezierPathElement*)previousElement forScale:(CGFloat)scale{
    scaleToDraw = scale;
    scaleTransform = CGAffineTransformMakeScale(scaleToDraw, scaleToDraw);
    return nil;
}


-(void) loadDataIntoVBOIfNeeded{
    // noop
}


-(void) draw{
    [self bind];
    
    
    [texture drawInContext:(JotGLContext*)[JotGLContext currentContext]
                      atT1:CGPointMake(0, 1)
                     andT2:CGPointMake(1, 1)
                     andT3:CGPointMake(0, 0)
                     andT4:CGPointMake(1, 0)
                      atP1:CGPointApplyAffineTransform(p1, scaleTransform)
                     andP2:CGPointApplyAffineTransform(p2, scaleTransform)
                     andP3:CGPointApplyAffineTransform(p3, scaleTransform)
                     andP4:CGPointApplyAffineTransform(p4, scaleTransform)
            withResolution:texture.pixelSize
                   andClip:NO
           andClippingSize:CGSizeZero
                   asErase:YES]; // erase
    
    //
    // should make a drawInQuad: method that takes four points
    // i can just translate the mmscrap corners into the main page
    // coordinates, and send these four points into the draw call
    //
    // will also need to set the blend mode to make it erase instead of
    // draw, once i have the location in the right place
    [self unbind];
}


/**
 * this method has become quite a bit more complex
 * than it was originally.
 *
 * when this method is called from a background thread,
 * it will generate and bind the VBO only. it won't create
 * a VAO
 *
 * when this method is called on the main thread, it will
 * create the VAO, and will also create the VBO to go with
 * it if needed. otherwise it'll bind the VBO from the
 * background thread into the VAO
 *
 * the [unbind] method will unbind either the VAO or VBO
 * depending on which was created/bound in this method+thread
 */
-(BOOL) bind{
    [texture bind];
    return YES;
}

-(void) unbind{
    [texture unbind];
    // noop
}


-(void) dealloc{
    texture = nil;
}

/**
 * helpful description when debugging
 */
-(NSString*)description{
    return @"[FilledPathSegment]";
}


#pragma mark - PlistSaving

-(NSDictionary*) asDictionary{
    NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithDictionary:[super asDictionary]];
    
    [dict setObject:[NSKeyedArchiver archivedDataWithRootObject:path] forKey:@"bezierPath"];
    
    [dict setObject:[NSNumber numberWithFloat:p1.x] forKey:@"p1.x"];
    [dict setObject:[NSNumber numberWithFloat:p1.y] forKey:@"p1.y"];
    [dict setObject:[NSNumber numberWithFloat:p2.x] forKey:@"p2.x"];
    [dict setObject:[NSNumber numberWithFloat:p2.y] forKey:@"p2.y"];
    [dict setObject:[NSNumber numberWithFloat:p3.x] forKey:@"p3.x"];
    [dict setObject:[NSNumber numberWithFloat:p3.y] forKey:@"p3.y"];
    [dict setObject:[NSNumber numberWithFloat:p4.x] forKey:@"p4.x"];
    [dict setObject:[NSNumber numberWithFloat:p4.y] forKey:@"p4.y"];

    return [NSDictionary dictionaryWithDictionary:dict];
}

-(id) initFromDictionary:(NSDictionary*)dictionary{
    self = [super initFromDictionary:dictionary];
    if (self) {
        // load from dictionary
        path = [NSKeyedUnarchiver unarchiveObjectWithData:[dictionary objectForKey:@"bezierPath"]];
        p1 = CGPointMake([[dictionary objectForKey:@"p1.x"] floatValue], [[dictionary objectForKey:@"p1.y"] floatValue]);
        p2 = CGPointMake([[dictionary objectForKey:@"p2.x"] floatValue], [[dictionary objectForKey:@"p2.y"] floatValue]);
        p3 = CGPointMake([[dictionary objectForKey:@"p3.x"] floatValue], [[dictionary objectForKey:@"p3.y"] floatValue]);
        p4 = CGPointMake([[dictionary objectForKey:@"p4.x"] floatValue], [[dictionary objectForKey:@"p4.y"] floatValue]);
        
        NSUInteger prime = 31;
        hashCache = 1;
        hashCache = prime * hashCache + p1.x;
        hashCache = prime * hashCache + p1.y;
        hashCache = prime * hashCache + p2.x;
        hashCache = prime * hashCache + p2.y;
        hashCache = prime * hashCache + p3.x;
        hashCache = prime * hashCache + p3.y;
        hashCache = prime * hashCache + p4.x;
        hashCache = prime * hashCache + p4.y;

        [self generateTextureFromPath];
    }
    return self;
}

/**
 * if we ever change how we render segments, then the data that's stored in our
 * dataVertexBuffer will contain "bad" data, since it would have been generated
 * for an older/different render method.
 *
 * we need to validate that we have the exact number of bytes of data to render
 * that we think we do
 */
-(void) validateDataGivenPreviousElement:(AbstractBezierPathElement*)previousElement{
    // noop
}

-(UIBezierPath*) bezierPathSegment{
    return path;
}


#pragma mark - hashing and equality

-(NSUInteger) hash{
    return hashCache;
}

-(BOOL) isEqual:(id)object{
    return self == object || [self hash] == [object hash];
}

@end
