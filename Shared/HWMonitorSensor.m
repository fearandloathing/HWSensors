//
//  NSHardwareMonitorSensor.m
//  HWSensors
//
//  Created by kozlek on 23/02/12.
//  Copyright (c) 2012 kozlek. All rights reserved.
//

#import "HWMonitorSensor.h"

#include "FakeSMCDefinitions.h"

inline UInt8 get_index(char c)
{
	return c > 96 && c < 103 ? c - 87 : c > 47 && c < 58 ? c - 48 : 0;
};

@implementation HWMonitorSensor

@synthesize key;
@synthesize type;
@synthesize group;
@synthesize caption;
@synthesize data;
@synthesize disk;

@synthesize level;
@synthesize value;

@synthesize favorite;
@synthesize extendedFormat;
@synthesize valueHasBeenChanged;
@synthesize levelHasBeenChanged;

@synthesize menuItem;

+ (int)getIndexOfHexChar:(char)c
{
	return c > 96 && c < 103 ? c - 87 : c > 47 && c < 58 ? c - 48 : 0;
}

+ (HWMonitorSensor*)sensor
{
    HWMonitorSensor *me = [[HWMonitorSensor alloc] init];
    
    if (me) {
        me->levelHasBeenChanged = true;
        me->valueHasBeenChanged = true;
        
        return me;
    }
    
    return nil;
}

- (void)setType:(NSString *)newType
{
    if (![type isEqualToString:newType]) { 
        self->valueHasBeenChanged = true;
        self->type = newType;
    }
}

- (NSString *)type
{
    self->valueHasBeenChanged = false;
    return self->type;
}

- (void)setData:(NSData *)newData
{
    if (![data isEqualToData:newData]) {
        self->valueHasBeenChanged = true;
        self->data = newData;
    }
}

- (NSData *)data
{
    self->valueHasBeenChanged = false;
    return self->data;
}

- (void)setLevel:(NSUInteger)newLevel
{
    if (level != newLevel) {
        self->levelHasBeenChanged = true;
        self->level = newLevel;
    }
}

- (NSUInteger)level
{
    self->levelHasBeenChanged = false;
    return self->level;
}

- (float)decodeValue
{
    if (type && data) {
        if (([type characterAtIndex:0] == 'u' || [type characterAtIndex:0] == 's') && [type characterAtIndex:1] == 'i') {
            
            BOOL signd = [type characterAtIndex:0] == 's';
            
            switch ([type characterAtIndex:2]) {
                case '8':
                    if ([type characterAtIndex:3] == '\0' && [data length] == 1) {
                        UInt8 encoded = 0;
                        
                        bcopy([data bytes], &encoded, 1);
                        
                        return (signd && encoded & 0x80 ? -encoded : encoded);
                    }
                    break;
                    
                case '1':
                    if ([type characterAtIndex:3] == '6' && [data length] == 2) {
                        UInt16 encoded = 0;
                        
                        bcopy([data bytes], &encoded, 2);
                        
                        encoded = OSSwapBigToHostInt16(encoded);
                        
                        return (signd && encoded & 0x8000 ? -encoded : encoded);
                    }
                    break;
                    
                case '3':
                    if ([type characterAtIndex:3] == '2' && [data length] == 4) {
                        UInt32 encoded = 0;
                        
                        bcopy([data bytes], &encoded, 4);
                        
                        encoded = OSSwapBigToHostInt32(encoded);
                        
                        return (signd && encoded & 0x80000000 ? -encoded : encoded);
                    }
                    break;
            }
        }
        else if (([type characterAtIndex:0] == 'f' || [type characterAtIndex:0] == 's') && [type characterAtIndex:1] == 'p' && [data length] == 2) {
            UInt16 encoded = 0;
            
            bcopy([data bytes], &encoded, 2);
            
            UInt8 i = [HWMonitorSensor getIndexOfHexChar:[type characterAtIndex:2]];
            UInt8 f = [HWMonitorSensor getIndexOfHexChar:[type characterAtIndex:3]];
            
            if (i + f != ([type characterAtIndex:0] == 's' ? 15 : 16) ) 
                return 0;
            
            UInt16 swapped = OSSwapBigToHostInt16(encoded);
            
            BOOL minus = swapped & 0x8000;
            
            if (minus) 
                swapped = swapped & 0x7fff;
            
            return ((float)swapped / (float)(0x1 << f)) * ([type characterAtIndex:0] == 's' && minus ? -1 : 1);
        }
    }
    
    return 0;
}

- (NSString*)value
{
    if (valueHasBeenChanged && data) {
        switch (group) {
            case kSMARTSensorGroupTemperature: {
                UInt16 t = 0;
                
                [data getBytes:&t length:2];
                               
                if (level != kHWSensorLevelExceeded && [disk isRotational])
                    [self setLevel:t >= 55 ? kHWSensorLevelExceeded : t >= 50 ? kHWSensorLevelHigh : t >= 40 ? kHWSensorLevelModerate : kHWSensorLevelNormal];
                
                self->value = [[NSString alloc] initWithFormat:@"%d°",t];
                break;
            }
                
            case kSMARTSensorGroupRemainingLife: {
                UInt64 life = 0;
                
                [data getBytes:&life length:[data length]];
                
                if (level != kHWSensorLevelExceeded)
                    [self setLevel:life >= 90 ? kHWSensorLevelExceeded : life >= 80 ? kHWSensorLevelHigh : life >= 70 ? kHWSensorLevelModerate : kHWSensorLevelNormal];
                
                self->value = [[NSString alloc] initWithFormat:@"%d%C",100-life,0x0025];
                break;
            }
                
            case kSMARTSensorGroupRemainingBlocks: {
                UInt64 blocks = 0;
                
                [data getBytes:&blocks length:[data length]];
                 
                self->value = [[NSString alloc] initWithFormat:@"%d",blocks];
                break;
            }
                
            case kHWSensorGroupTemperature: {
                float t = [self decodeValue];
                
                [self setLevel:t >= 100 ? kHWSensorLevelExceeded : t >= 85 ? kHWSensorLevelHigh : t >= 70 ? kHWSensorLevelModerate : kHWSensorLevelNormal];
                
                self->value = [[NSString alloc] initWithFormat:@"%1.0f°", t];
                break;
            }
                
            case kHWSensorGroupVoltage:
                self->value = [[NSString alloc] initWithFormat:@"%1.3fV", [self decodeValue]];
                break;
                
            case kHWSensorGroupTachometer: {
                
                float rpm = [self decodeValue];
                
                [self setLevel:rpm == 0 ? kHWSensorLevelExceeded : kHWSensorLevelNormal];
                
                if (rpm == 0)
                    return [[NSString alloc] initWithString:@"-"];
                
                if ([self extendedFormat])
                    return [[NSString alloc] initWithFormat:@"%1.0f%C", rpm, 0x0025];
                
                self->value = [[NSString alloc] initWithFormat:@"%1.0frpm", rpm];
                break;
            }
                
            /*case kHWSensorGroupMultiplier:
                self->value = [[NSString alloc] initWithFormat:@"x%1.1f", [self decodeValue]];
                break;*/
                
            case kHWSensorGroupFrequency: {
                float f = [self decodeValue];
                
                if ([self extendedFormat])
                    self->value = [[NSString alloc] initWithFormat:@"x%1.1f", [self decodeValue]];
                else if (f > 1e6)
                    self->value = [[NSString alloc] initWithFormat:@"%1.2fTHz", f / 1e6];
                else if (f > 1e3)
                    self->value = [[NSString alloc] initWithFormat:@"%1.2fGHz", f / 1e3];
                else 
                    self->value = [[NSString alloc] initWithFormat:@"%1.0fMHz", f]; 
                break;
            }
                
            default:
                self->value = [[NSString alloc] initWithString:@"-"];
                break;
        }
    }
    
    return self->value;
}

@end
