//
//  InterfaceController.h
//  TestApp WatchKit Extension
//
//  Created by Damien DeVille on 2/13/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <WatchKit/WatchKit.h>

@interface InterfaceController : WKInterfaceController

@property (strong, nonatomic) IBOutlet WKInterfaceTable *table;

@end
