//
//  main.m
//  10.1__weak底层原理
//
//  Created by 刘光强 on 2020/2/14.
//  Copyright © 2020 guangqiang.liu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Person.h"

void __strongTest() {
    // 强指针person1，注意当我们不写__strong时，默认就是__strong修饰
    __strong typeof(Person) *person1;

    NSLog(@"111");
    
    {
        Person *person = [[Person alloc] init];
        // person1强指针强引用着person对象
        person1 = person;
        NSLog(@"222");
    }
    
    NSLog(@"%@", person1);
    
    [person1 run];
    
    NSLog(@"333");
}

void __weakTest() {
    // 弱指针person2
    __weak typeof(Person) *person2;

    NSLog(@"111");
    
    {
        Person *person = [[Person alloc] init];
        // person2弱指针弱引用着person对象
        person2 = person;
        NSLog(@"222");
    }
    
    NSLog(@"%@", person2);
    
    [person2 run];
    
    NSLog(@"333");
}

void __unsafe_unretainedTest() {
    // 弱指针person3
    __unsafe_unretained typeof(Person) *person3;

    NSLog(@"111");
    
    {
        Person *person = [[Person alloc] init];
        // person3弱指针弱引用着person对象
        person3 = person;
        NSLog(@"222");
    }
    
    NSLog(@"%@", person3);
    
    // Thread 1: EXC_BAD_ACCESS (code=1, address=0x101803f0)
    [person3 run];
    
    NSLog(@"333");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
//        __strongTest();
//        __weakTest();
        __unsafe_unretainedTest();
    }
    
    NSLog(@"444");
    return 0;
}
