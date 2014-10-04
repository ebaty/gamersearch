//
//  RegionController.m
//  GamerSearch
//
//  Created by Masaki EBATA on 2014/09/21.
//  Copyright (c) 2014年 Masaki EBATA. All rights reserved.
//

#import "RegionController.h"
#import "BTController.h"

#define kRegionRadius 5.0f
#define kApplication [UIApplication sharedApplication]

@interface RegionController () <CLLocationManagerDelegate>

@property (nonatomic) CLLocationManager *manager;
@property (nonatomic) NSArray *monitoringGameCenters;

@end

@implementation RegionController

- (id)init {
    self = [super init];
    if ( self ) {
        _manager = [[CLLocationManager alloc] init];
        _manager.delegate = self;
        [_manager startUpdatingLocation];
    }
    return self;
}

- (void)setGameCenters:(NSArray *)gameCenters location:(CLLocation *)myLocation {
    NSMutableArray *sortedGameCenters = [NSMutableArray new];
    
    for ( NSDictionary *gameCenter in gameCenters ) {
        CLLocation *gameCenterLocation =
            [[CLLocation alloc] initWithLatitude:[gameCenter[@"latitude"]  doubleValue]
                                       longitude:[gameCenter[@"longitude"] doubleValue]];
        CLLocationDistance distance = [myLocation distanceFromLocation:gameCenterLocation];
        
        NSMutableDictionary *newParams = [gameCenter mutableCopy];
        [newParams setObject:@(distance) forKey:@"distance"];
        
        [sortedGameCenters addObject:newParams];
    }
    
    NSSortDescriptor *descriptor = [[NSSortDescriptor alloc] initWithKey:@"distance"  ascending:YES];
    self.monitoringGameCenters = [sortedGameCenters sortedArrayUsingDescriptors:@[descriptor]];
}

- (void)setMonitoringGameCenters:(NSArray *)monitoringGameCenters {
    _monitoringGameCenters = monitoringGameCenters;
    int count = (int)monitoringGameCenters.count;
    if ( count > 20 ) count = 20;
    
    for ( CLRegion *region in _manager.monitoredRegions ) {
        [_manager stopMonitoringForRegion:region];
    }
    
    DDLogVerbose(@"%@:%@", NSStringFromSelector(_cmd), monitoringGameCenters);
    for ( int i = 0; i < count; ++i ) {
        NSDictionary *gameCenter = monitoringGameCenters[i];
        
        CLLocationCoordinate2D coordinate =
            CLLocationCoordinate2DMake([gameCenter[@"latitude"] doubleValue], [gameCenter[@"longitude"] doubleValue]);
        
        CLCircularRegion *region =
            [[CLCircularRegion alloc] initWithCenter:coordinate radius:kRegionRadius identifier:gameCenter[@"name"]];
        
        [_manager startMonitoringForRegion:region];
#ifdef DEBUG
        [_manager requestStateForRegion:region];
#endif
    }
    
}

- (void)checkDistance:(NSDictionary *)gameCenter nowLocation:(CLLocation *)nowLocation {
    if ( gameCenter ) {
        CLLocationCoordinate2D coordinate =
            CLLocationCoordinate2DMake([gameCenter[@"latitude"] doubleValue], [gameCenter[@"longitude"] doubleValue]);
        
        CLLocation *gameCenterLocation =
            [[CLLocation alloc] initWithLatitude:[gameCenter[@"latitude"]  doubleValue]
                                       longitude:[gameCenter[@"longitude"] doubleValue]];
        
        CLCircularRegion *region =
            [[CLCircularRegion alloc] initWithCenter:coordinate radius:kRegionRadius identifier:gameCenter[@"name"]];
        
        CLLocationDistance distance = [nowLocation distanceFromLocation:gameCenterLocation];

        if ( distance <= kRegionRadius * 20 ) {
            [self locationManager:_manager didEnterRegion:region];
        }else {
            [self locationManager:_manager didExitRegion:region];
        }
    }
}

#pragma mark - CLLocationManager delegate methods.

#pragma mark 位置情報更新
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *nowLocation = locations.lastObject;
    DDLogVerbose(@"%@", NSStringFromSelector(_cmd));
    
    if ( _gameCenters ) {
        [self setGameCenters:_gameCenters location:nowLocation];
        [self checkDistance:_monitoringGameCenters.firstObject nowLocation:nowLocation];
    }
    
    [manager stopUpdatingLocation];
    [manager performSelector:@selector(startUpdatingLocation) withObject:nil afterDelay:5 * 60];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    DDLogError(@"%@:%@", NSStringFromSelector(_cmd), error);
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region {
    NSArray *stateArray = @[@"CLRegionStateUnknown",
                            @"CLRegionStateInside",
                            @"CLRegionStateOutside"];
    
    CLCircularRegion *r = (CLCircularRegion *)region;
    CLLocation *regionLocation = [[CLLocation alloc] initWithLatitude:r.center.latitude longitude:r.center.longitude];
    DDLogVerbose(@"%@:%@, %lf", region.identifier, stateArray[state], [manager.location distanceFromLocation:regionLocation]);
}

#pragma mark 領域観測
- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region
{
    [BTController backgroundTask:^{
        [kApplication cancelAllLocalNotifications];
        
        // デバッグ用
        CLCircularRegion *circular = (CLCircularRegion *)region;
        CLLocation *regionLocation = [[CLLocation alloc] initWithLatitude:circular.center.latitude longitude:circular.center.longitude];
        DDLogVerbose(@"%@:%@, distance == %lf",
                     NSStringFromSelector(_cmd), region, [manager.location distanceFromLocation:regionLocation]);
        
        NSString *message = [region.identifier stringByAppendingString:@" に来ました"];
        
        NSDictionary *userInfo =
        @{
          @"message":message,
          @"state":@"EnterRegion",
          @"gameCenter":region.identifier
          };
        
        [self sendLocalNotification:message userInfo:userInfo];
    }];
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region
{
    [BTController backgroundTask:^{
        [kApplication cancelAllLocalNotifications];
        DDLogVerbose(@"%@:%@", NSStringFromSelector(_cmd), region);
        
        NSString *message = [region.identifier stringByAppendingString:@" を出ました"];
        
        NSDictionary *userInfo =
        @{
          @"message":message,
          @"state":@"ExitRegion",
          @"gameCenter":region.identifier
          };
        
        [self sendLocalNotification:message userInfo:userInfo];
    }];
}

#pragma mark - Send notification method.
- (void)sendLocalNotification:(NSString *)message userInfo:(NSDictionary *)userInfo{
    [kApplication cancelAllLocalNotifications];
    
    UILocalNotification *notification = [UILocalNotification new];
    notification.fireDate  = [NSDate dateWithTimeIntervalSinceNow:3 * 60];
    notification.alertBody = message;
    notification.timeZone  = [NSTimeZone localTimeZone];
    notification.soundName = UILocalNotificationDefaultSoundName;
    notification.userInfo = userInfo;

    [kApplication scheduleLocalNotification:notification];
}

@end
