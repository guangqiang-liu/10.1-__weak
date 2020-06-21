//
//  Person.m
//  10.1__weak底层原理
//
//  Created by 刘光强 on 2020/2/14.
//  Copyright © 2020 guangqiang.liu. All rights reserved.
//

#import "Person.h"

@implementation Person

- (void)run {
    NSLog(@"%s", __func__);
}

// 当person对象销毁了，需要找到指向这个person对象的所有弱指针，将这些弱指针全部清空
- (void)dealloc {
    NSLog(@"%s", __func__);
}
@end
