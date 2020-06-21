# 10.1 __weak底层原理

我们在平时的开发过程中，经常会使用到`__weak`关键字来解决循环引用的问题，被`__weak`修饰的指针就变成了弱指针，当这个弱指针指向的对象销毁时，会自动将这个弱指针的值置为`nil`，那么它的底层实现原理又是怎样尼？

我们先来了解下弱引用的两个常见关键字：

* __weak
* __unsafe_unretained

接下来我们创建一个新的工程，然后创建一个`Person`类，来研究下强引用和弱引用的区别，示例代码如下：

`Person`类

```
@interface Person : NSObject

- (void)run;
@end


@implementation Person

- (void)run {
    NSLog(@"%s", __func__);
}

// 当person对象销毁时，需要找到指向这个person对象的所有弱指针，将这些弱指针全部清空
- (void)dealloc {
    NSLog(@"%s", __func__);
}
@end
```

`main.m`

```
void __strongTest() {
    // 强指针person1
    // 注意：当我们不写__strong时，系统默认就是__strong修饰，这里为了加强对比才写上__strong
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
        __strongTest();
        __weakTest();
        __unsafe_unretainedTest();
    }
    
    NSLog(@"444");
    return 0;
}
```

上面示例代码中，我们创建了三个函数`__strongTest`，`__weakTest`，`__unsafe_unretainedTest`，我们逐一的来分析下`person`对象的销毁时机

首先我们执行`__strongTest`函数，我们通过打印可以看到`person`对象是在` NSLog(@"333");`和` NSLog(@"444");`之间释放的，这个很好理解。因为`person1`指针是`__strong`修饰的，是个强指针，`person1`强指针强引用着`person`对象，所以`person`对象只有出了`@autoreleasepool{}`大括号的作用域才销毁，如果没有`person1`指针强引用，那么`person`对象在执行完` NSLog(@"222");`后便就释放了

我们再来执行`__strongTest`函数，我们通过打印可以发现，`person`对象在执行完`NSLog(@"222");`就释放了，并且打印的`person2`指针为`null`，执行`[person2 run];`也并没有打印`run`方法的信息

这是因为`person2`指针为弱指针，对`person`对象产生的是弱引用，所以执行完`NSLog(@"222");`后`person`对象就销毁了，指向对象的弱指针`preson2`也就置为`nil`

我们再来执行`__unsafe_unretainedTest`函数，我们通过打印可以看出，`person`对象在执行完`NSLog(@"222");`后就释放了，并且打印`person3`指针还有值，但是执行`[person3 run];`时，我们发现程序抛出异常`Thread 1: EXC_BAD_ACCESS (code=1, address=0x101803f0)`

这是因为`person3`指针也是弱指针，并且是`__unsafe_unretained`关键字修饰的弱指针，`person3`弱指针对`person`对象产生的是弱引用，所以`person`对象当离开大括号的作用域就销毁了。虽然`person`对象销毁了，但是`person3`指针任然有值，指向着`person`对象已经销毁的内存地址，所以当执行`[person3 run];`语句时，程序就抛出异常，报坏内存访问

从上面的三个函数的执行结果我们可以得出结论：
> `__weak`和`__unsafe_unretained`这两个关键字都能产生弱引用，但是它们又有以下不同：
> 
>> `__weak`产生的弱引用，当弱指针指向的对象销毁时，也会将这个弱指针的值置为`nil`
> 
>> `__unsafe_unretained`产生的弱引用，当弱指针指向的对象销毁时，并不能将这个弱指针的值置为nil，这样就容易造成坏内存访问的异常

所以在平时的开发过程中，我们优先选择使用`__weak`关键字来实现弱引用

---

上面总结到使用`__weak`可以在指向的对象销毁时，会将弱指针的值置为`nil`，接下来我们通过底层源码来加以验证

底层源码的跟踪路径：`objc4源码 -> NSObject.mm -> dealloc() -> _objc_rootDealloc() -> rootDealloc() -> object_dispose() -> objc_destructInstance() -> clearDeallocating() -> clearDeallocating_slow() -> weak_clear_no_lock()`

下面对源码流程的核心流程进行些分析讲解：

我们都知道当一个对象即将要销毁时，就会调用这个类的`dealloc`函数来销毁对象，objc底层源码中的`dealloc`函数如下：

```
// Replaced by NSZombies
- (void)dealloc {
    
    // self为当前调用`dealloc`函数的对象，也就是待销毁的对象
    _objc_rootDealloc(self);
}
```

接着执行`_objc_rootDealloc(self);`函数，源码如下：

```
void
_objc_rootDealloc(id obj)
{
    assert(obj);

    obj->rootDealloc();
}
```

执行`obj->rootDealloc()`函数，源码如下：

```
inline void
objc_object::rootDealloc()
{
    if (isTaggedPointer()) return;  // fixme necessary?

    // 判断是否为普通isa指针，是否有弱引用等判断
    if (fastpath(isa.nonpointer  &&  
                 !isa.weakly_referenced  &&  
                 !isa.has_assoc  &&  
                 !isa.has_cxx_dtor  &&  
                 !isa.has_sidetable_rc)) {
        
        assert(!sidetable_present());
        
        // 如果是`nonpointer`，或者没有`weakly_referenced`等，释放的更快
        free(this);
    }
    else {
        // 此时的`this`为`person`对象，也就是待释放的对象
        object_dispose((id)this);
    }
}
```

在`rootDealloc()`函数中，我们看到有一些`isa.nonpointer`，`isa.weakly_referenced`等，这些都是优化过的`isa`指针中存储的信息

优化过的`isa`结构如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200215-153404@2x.png)

`nonpointer`，`has_assoc`等结构体成员对应的解释如图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200215-153416@2x.png)

接着执行`object_dispose((id)this);`函数，源码如下：

```
id 
object_dispose(id obj)
{
    if (!obj) return nil;

    // 在释放对象前，做一些释放前的清理工作，例如弱引用指针的清空操作
    objc_destructInstance(obj);
    
    // 释放对象
    free(obj);

    return nil;
}
```

在`object_dispose()`函数中，我们可以看到，在执行`free(obj);`释放对象前，还会执行`objc_destructInstance(obj);`来做一些释放前的准备工作，清除弱指针就是在这准备工作中完成的

接下来执行`objc_destructInstance(obj);`函数，源码如下：

```
/***********************************************************************
* objc_destructInstance
* Destroys an instance without freeing memory. 
* Calls C++ destructors.
* Calls ARC ivar cleanup.
* Removes associative references.
* Returns `obj`. Does nothing if `obj` is nil.
**********************************************************************/
void *objc_destructInstance(id obj) 
{

    if (obj) {
        // Read all of the flags at once for performance.
        
        // 判断是否有析构函数
        bool cxx = obj->hasCxxDtor();
        
        // 判断是否有关联对象
        bool assoc = obj->hasAssociatedObjects();

        // This order is important.
        
        // 清理成员变量
        if (cxx) object_cxxDestruct(obj);
        
        // 移除关联对象，关联对象移除时机在此函数中执行
        if (assoc) _object_remove_assocations(obj);
        
        // 将指向当前对象的弱指针置为nil
        obj->clearDeallocating();
    }

    return obj;
}
```

接下来调用`obj->clearDeallocating();`函数，源码如下：

```
inline void 
objc_object::clearDeallocating()
{
    if (slowpath(!isa.nonpointer)) { // 普通的isa指针
        // Slow path for raw pointer isa.
        sidetable_clearDeallocating();
    }
    else if (slowpath(isa.weakly_referenced  ||  isa.has_sidetable_rc)) { // 存在弱引用或者has_sidetable_rc中存储有引用计数
        
        // Slow path for non-pointer isa with weak refs and/or side table data.

        // 清空弱指针
        clearDeallocating_slow();
    }

    assert(!sidetable_present());
}
```

接下来执行`clearDeallocating_slow();`函数，源码如下：

```
inline void 
objc_object::clearDeallocating()
{
    if (slowpath(!isa.nonpointer)) { // 普通的isa指针
        // Slow path for raw pointer isa.
        sidetable_clearDeallocating();
    }
    else if (slowpath(isa.weakly_referenced  ||  isa.has_sidetable_rc)) { // 被弱引用指向过，或者是has_sidetable_rc值为1，当has_sidetable_rc为1说明引用计数就存储在`sidetable中`
        
        // Slow path for non-pointer isa with weak refs and/or side table data.

        // 清空弱指针
        clearDeallocating_slow();
    }

    assert(!sidetable_present());
}
```

这里我们需要注意：`isa.has_sidetable_rc`，当`has_sidetable_rc`值为1时，这时就说明`isa`指针中存储不下引用计数了，引用计数需要存储在`Sidetable`结构体中

接下来执行`clearDeallocating_slow();`函数，源码如下：

```
// Slow path of clearDeallocating() 
// for objects with nonpointer isa
// that were ever weakly referenced 
// or whose retain count ever overflowed to the side table.
NEVER_INLINE void
objc_object::clearDeallocating_slow()
{
    assert(isa.nonpointer  &&  (isa.weakly_referenced || isa.has_sidetable_rc));

    // 通过`[this]`找到`table`，`[this]`：对象的内存地址
    SideTable& table = SideTables()[this];
    
    // 加锁操作
    table.lock();
    
    // 判断是否被弱引用指引用过
    if (isa.weakly_referenced) {
        // table.weak_table：取出weak_table(全局弱引用表)
        weak_clear_no_lock(&table.weak_table, (id)this);
    }
    
    // 如果引用计数存储在`SideTable`中
    if (isa.has_sidetable_rc) {
        // 将这个对象的引用计数 从存储引用计数的表中移除掉
        table.refcnts.erase(this);
    }
    
    // 解锁操作
    table.unlock();
}
```

这里的`SideTable`结构体就是用来存储引用计数的底层结构

接下来执行`weak_clear_no_lock(&table.weak_table, (id)this);`函数，源码如下：

```
/**
 * ！！！清除弱指针的核心函数
 *
 * Called by dealloc; nils out all weak pointers that point to the 
 * provided object so that they can no longer be used.
 * 
 * @param weak_table 
 * @param referent The object being deallocated. 
 */
void 
weak_clear_no_lock(weak_table_t *weak_table, id referent_id)
{
    // referent_id：待释放的对象
    
    // 将referent_id强制转换为`(objc_object *)`类型
    objc_object *referent = (objc_object *)referent_id;

    // 通过对象的内存地址在全局弱引用表中找到这个对象的弱引用表(entry)，这个表中存放的都是指向这个对象的弱指针
    weak_entry_t *entry = weak_entry_for_referent(weak_table, referent);
    
    if (entry == nil) {
        /// XXX shouldn't happen, but does with mismatched CF/objc
        //printf("XXX no entry for clear deallocating %p\n", referent);
        return;
    }

    // weak_referrer_t结构体官方解释：The address of a __weak variable.
    
    // 变量referrers：即为弱指针内存地址的集合
    // zero out references
    weak_referrer_t *referrers;
    
    // 这个对象对应的弱引用表的大小
    size_t count;
    
    if (entry->out_of_line()) {
        // 取出referrers
        referrers = entry->referrers;
        
        // 获取对象所对应的弱引用表的长度
        count = TABLE_SIZE(entry);
    } 
    else {
        // 取出referrers
        referrers = entry->inline_referrers;
        count = WEAK_INLINE_COUNT;
    }
    
    // 遍历这个对象所对应的弱引用表
    for (size_t i = 0; i < count; ++i) {
        // referrers：弱指针的集合
        // `*referrer`：为弱引用指针的内存地址
        objc_object **referrer = referrers[i];
        
        // 如果内存地址有值
        if (referrer) {
            if (*referrer == referent) {
                // 将弱引用指针的值赋值为nil，也就是说__weak修饰的对象释放时，将弱指针置为nil就是在此完成的
                *referrer = nil;
            }
            else if (*referrer) {
                _objc_inform("__weak variable at %p holds %p instead of %p. "
                             "This is probably incorrect use of "
                             "objc_storeWeak() and objc_loadWeak(). "
                             "Break on objc_weak_error to debug.\n", 
                             referrer, (void*)*referrer, (void*)referent);
                objc_weak_error();
            }
        }
    }
    
    // 将这个对象所对应的弱引用表(entry)从全局弱引用表(weak_table)中移除掉
    weak_entry_remove(weak_table, entry);
}
```

最终一个对象销毁时，将这个对象的所有弱指针的值置为`nil`的操作就是下面这段代码：

```
	// 遍历这个对象所对应的弱引用表
    for (size_t i = 0; i < count; ++i) {
        // referrers：弱指针的集合
        // `*referrer`：为弱引用指针的内存地址
        objc_object **referrer = referrers[i];
        
        // 如果内存地址有值
        if (referrer) {
            if (*referrer == referent) {
                // 将弱引用指针的值赋值为nil，也就是说__weak修饰的对象释放时，将弱指针置为nil就是在此完成的
                *referrer = nil;
            }
            else if (*referrer) {
                _objc_inform("__weak variable at %p holds %p instead of %p. "
                             "This is probably incorrect use of "
                             "objc_storeWeak() and objc_loadWeak(). "
                             "Break on objc_weak_error to debug.\n", 
                             referrer, (void*)*referrer, (void*)referent);
                objc_weak_error();
            }
        }
    }
```

在`weak_clear_no_lock(&table.weak_table, (id)this);`函数中，还有一个很核心的函数调用，就是`weak_entry_t *entry = weak_entry_for_referent(weak_table, referent);` 

这个函数的作用就是在全局弱引用表中，通过对象的内存地址作为`key`，然后用这个`key` & `weak_table->mask`得到一个哈希表的索引值，通过这个索引值在全局弱引用表中(哈希表)找到这个对象的弱引用表

`weak_entry_for_referent(weak_table, referent)`函数，源码如下：

```
/** 
 * Return the weak reference table entry for the given referent. 
 * If there is no entry for referent, return NULL. 
 * Performs a lookup.
 *
 * @param weak_table 
 * @param referent The object. Must not be nil.
 *
 * 返回这个对象的弱引用表
 * @return The table of weak referrers to this object. 
 */
static weak_entry_t *
weak_entry_for_referent(weak_table_t *weak_table, objc_object *referent)
{
    assert(referent);

    // referent为当前对象
    
    // 指向对象的所有weak指针的集合
    weak_entry_t *weak_entries = weak_table->weak_entries;

    if (!weak_entries) return nil;

    // 根据对象的内存址值 & mask 找到一个索引值，也就是说对象的内存地址作为key
    size_t begin = hash_pointer(referent) & weak_table->mask;
    
    // 哈希表中的索引值
    size_t index = begin;
    
    size_t hash_displacement = 0;
    
    while (weak_table->weak_entries[index].referent != referent) {
        index = (index+1) & weak_table->mask;
        if (index == begin) bad_weak_table(weak_table->weak_entries);
        hash_displacement++;
        if (hash_displacement > weak_table->max_hash_displacement) {
            return nil;
        }
    }
    
    // 通过索引值index，在全局弱引用表中找到对应的value，这个value就是一个对象的弱引用表
    return &weak_table->weak_entries[index];
}
```

从上面的源码中我们可以看到，源码`size_t begin = hash_pointer(referent) & weak_table->mask;`和`&weak_table->weak_entries[index];`

就是通过`hash_pointer(referent)`内存地址 & `weak_table->mask`得到一个哈希表的索引值，然在通过这个索引值就能找到哈希表中对应的`value`，而这个`value`就是一个对象对应的弱引用表

在`weak_clear_no_lock(&table.weak_table, (id)this);`函数中，当我们循环遍历清除了这个对象的所有弱指针后，还执行了` weak_entry_remove(weak_table, entry);`函数，源码如下：

```
/**
 * 从全局弱引用表中移除这个对象所对应的弱引用表
 * Remove entry from the zone's table of weak references.
 */
static void weak_entry_remove(weak_table_t *weak_table, weak_entry_t *entry)
{
    // remove entry
    if (entry->out_of_line()) free(entry->referrers);
    
    bzero(entry, sizeof(*entry));

    // 全局弱引用表的长度 - 1
    weak_table->num_entries--;

    weak_compact_maybe(weak_table);
}
```

这个函数作用是将这个对象所对应的弱引用表(entry)从全局弱引用表(weak_table)中移除掉

在这个清除弱指针的过程中，有以下几个结构我需要注意：

* SideTable
* weak_table_t
* weak_entry_t
* weak_referrer_t

下面我们在来看看这几个结构体的成员以及对核心成员的解释：

`SideTable`：

```
// 当isa中的`has_sidetable_rc`值为1时，说明引用计数是存储在SideTable结构体中
struct SideTable {
    
    // os_unfair_lock锁
    spinlock_t slock;
    
    // 存储引用计数值的表，哈希表数据结构
    RefcountMap refcnts;
    
    // 全局弱引用表，哈希表数据结构
    weak_table_t weak_table;

    SideTable() {
        memset(&weak_table, 0, sizeof(weak_table));
    }

    ~SideTable() {
        _objc_fatal("Do not delete SideTable.");
    }

    void lock() { slock.lock(); }
    void unlock() { slock.unlock(); }
    void forceReset() { slock.forceReset(); }

    // Address-ordered lock discipline for a pair of side tables.

    template<HaveOld, HaveNew>
    static void lockTwo(SideTable *lock1, SideTable *lock2);
    template<HaveOld, HaveNew>
    static void unlockTwo(SideTable *lock1, SideTable *lock2);
};
```

`weak_table_t`：

```
/**
 * weak_table_t为全局弱引用表结构（哈希表数据结构），对象的内存地址作为key，weak_entry_t为value
 *
 * The global weak references table. Stores object ids as keys,
 * and weak_entry_t structs as their values.
 */
struct weak_table_t {
    // weak_entries：weak_table_t结构中的全局弱引用表，也是所有的`weak_entry_t`单元的集合
    weak_entry_t *weak_entries;
    size_t    num_entries; // 全局弱引用表中存储的多少个对象的弱引用表的个数
    uintptr_t mask; // 对象的内存地址 & mask 得出一个哈希表的索引
    uintptr_t max_hash_displacement;
};
```

`weak_entry_t`：

```
// 某一个对象的所有弱指针的集合
struct weak_entry_t {
    
    DisguisedPtr<objc_object> referent;
    
    // 共用体
    union {
        struct {
            
            // The address of a __weak variable.
            // weak_referrer_t：官方解释：弱指针的内存地址
            
            // referrers：为某一个对象的所有弱指针地址的集合
            weak_referrer_t *referrers;
            
            uintptr_t        out_of_line_ness : 2;
            uintptr_t        num_refs : PTR_MINUS_2;
            
            // 这个mask即为一个对象的弱引用表中存储的弱指针的个数 - 1，这个和方法缓存中的缓存列表的长度逻辑一样
            uintptr_t        mask;
            uintptr_t        max_hash_displacement;
        };
        
        struct {
            // out_of_line_ness field is low bits of inline_referrers[1]
            weak_referrer_t  inline_referrers[WEAK_INLINE_COUNT];
        };
    };

    bool out_of_line() {
        return (out_of_line_ness == REFERRERS_OUT_OF_LINE);
    }

    weak_entry_t& operator=(const weak_entry_t& other) {
        memcpy(this, &other, sizeof(other));
        return *this;
    }

    
    weak_entry_t(objc_object *newReferent, objc_object **newReferrer)
        : referent(newReferent)
    {
        inline_referrers[0] = newReferrer;
        for (int i = 1; i < WEAK_INLINE_COUNT; i++) {
            inline_referrers[i] = nil;
        }
    }
};
```

`weak_referrer_t`：

```
// The address of a __weak variable.
// These pointers are stored disguised so memory analysis tools
// don't see lots of interior pointers from the weak table into objects.
typedef DisguisedPtr<objc_object *> weak_referrer_t;
```

我们对上面的四个结构的连系进行简单的总结：`SideTable`结构体中包含了`weak_table_t`，在`weak_table_t`中又包含了`weak_entry_t`，在`weak_entry_t`中又包含`weak_referrer_t`，它们是一层层的包含关系，关系图如下图：

![](https://imgs-1257778377.cos.ap-shanghai.myqcloud.com/QQ20200215-173929@2x.png)

到这里我们对`__weak`底层的源码分析就结束了，从底层源码中流程分析我们可以很清楚的看出`__weak`的查找弱引用表，和将弱指针置为`nil`的实现原理


讲解示例Demo地址：[https://github.com/guangqiang-liu/10.1-__weak]()


## 更多文章
* ReactNative开源项目OneM(1200+star)：**[https://github.com/guangqiang-liu/OneM](https://github.com/guangqiang-liu/OneM)**：欢迎小伙伴们 **star**
* iOS组件化开发实战项目(500+star)：**[https://github.com/guangqiang-liu/iOS-Component-Pro]()**：欢迎小伙伴们 **star**
* 简书主页：包含多篇iOS和RN开发相关的技术文章[http://www.jianshu.com/u/023338566ca5](http://www.jianshu.com/u/023338566ca5) 欢迎小伙伴们：**多多关注，点赞**
* ReactNative QQ技术交流群(2000人)：**620792950** 欢迎小伙伴进群交流学习
* iOS QQ技术交流群：**678441305** 欢迎小伙伴进群交流学习