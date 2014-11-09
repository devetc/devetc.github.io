---
layout: post
title: "Mutable Return Values"
date:   2014-11-08 18:57:58 -0800
categories: code
tags: cocoa
subtitle: Returning mutable objects is usually ok.
---

Over the past year I've had the opportunity to interview a couple dozen candidates for iOS positions (heavy in Objective-C) at Fitbit.
Early on in the process we discuss some commonly used concepts, plus do some light coding.
In particular we often ask the candidate to implement a method of the form:

{% highlight objc %}
- (NSArray *)manipulateSomeArray:(NSArray *)input;
{% endhighlight %}

The manipulation is straightforward[^non-disclose] — create an `NSMutableArray`, add some combination of the objects in then input array, then return the result.
As candidates talk through it, many have misconceptions about returning the intermediate `NSMutableArray`, versus returning a ‘plain’ `NSArray`.

[^non-disclose]: Because we plan to keep asking for the same task from new candidates, I won't be more specific.

Commonly, I'll hear that you can't or shouldn't return a mutable array because the compiler will be confused / angry / upset.
That's a load of crap.
More recently we use [CoderPad](https://coderpad.io/) with candidates, which provides the ability to actually run the compiler.
Upon seeing that returning the `NSMutableArray *` is totally fine, I've heard "Hmm, it works now, but I know I've seen the compiler get this wrong before".
(This may make the interviewer confused / angry / upset.)

I'll spit it out: Returning an `NSMutableArray *` value is permitted from a method that returns `NSArray *`, just as it would be from a method that returns `NSObject *`.
`NSMutableArray` is a subclass of `NSArray`, which means a *mutable array is an  array* (they have an [is-a](http://en.wikipedia.org/wiki/Is-a) relationship).
In plain C, you can return a `char *` value from a method typed as `void *` for similar reasons. There are **no language issues** with returning a mutable array.

{% highlight objc %}
- (NSArray *)arrayWithEveryOtherObjectInArray:(NSArray *)input {
    NSMutableArray *accumulator = [NSMutableArray new];
    for (NSUInteger i = 0; i < input.count; i += 2)
        [accumulator addObject:input[i]];
    return accumulator;
}
{% endhighlight %}

Another reason I've heard against returning the mutable instance is that it's bad form, because the caller could then cast it back to an `NSMutableArray` and mutate it.
That's strictly true, but has nothing do to with the method being called.
The caller could similarly just `free` the object pointer, and bad things would also happen.
There are rules that code must follow if it wants reasonable behavior! 

There are times where returning a mutable value is inappropriate, but this consideration is at the API design level — on syntax and semantic analysis levels it's fine.
Surprising behavior will arise when you return a mutable object *that is later mutated*.
Often this will manifest as a method returning a mutable instance variable, because instance variables are longer-lived than the above example's local variable.

For example, I'd expect the following assertion to hold:

{% highlight objc %}
NSView *view = [NSView new];
NSArray *oldSubviews = [view subviews];
[view addSubview:[NSButton new]];
NSArray *newSubviews = [view subviews];
asset([newSubviews count] > [oldSubviews count]);
{% endhighlight %}

If memory serves, this assertion would actually fail a few OS releases back.
The problem is not that the `-subviews` method returned a mutable array, the problem is that *it was mutated* after being returned.
For the `-subviews` getter to act in an unsurprising way, one approach is to copy the mutable array that it returns (making it immutable).
There are times where for performance it's desirable to avoid the copy; in this case, subviews are enumerated every time something needs to draw, which should happen a lot more frequently than adding or removing subviews.

To improve performance, the code could return the internal mutable array, while making a note that it has been returned externally.
Then when `-addSubview:` goes to modify the internal `subviews` mutable array, it first checks the flag and sees that it needs to make a new instance so it doesn't modify what has been given out.[^retain-count-opt]

[^retain-count-opt]: It might even be possible to optimize this further, by checking the retain count of the mutable array — if it's 1, even if the array had been returned before, the code *might* be able to infer that no one else has a reference to it, and modify it regardless of the "returned externally" flag. But beware, it wouldn't be possible to rely on this behavior before ARC — calling code might elide retain/release — which means it's probably not safe to rely on it under ARC-with-optimizations.

A similar issue exists with arguments. Consider this class (styled for brevity[^no-kvo]):

{% highlight objc %}
@interface NameParts : NSObject
@property (nonatomic, strong) NSString *fullName;
@property (nonatomic, readonly) NSString *firstName;
@end

@implementation NameParts
- (void)setFullName:(NSString *)fullName {
    _fullName = fullName;
    _firstName = [[fullName componentsSeparatedByString:@" "] firstObject];
}
@end
{% endhighlight %}

[^no-kvo]: The `firstName` property is changed without posting KVO notifications.

Which can be used like so:

{% highlight objc %}
NameParts *parts = [NameParts new];
parts.fullName = @"John Smith";
parts.firstName // => @"John"
{% endhighlight %}

This has a problem with mutability:

{% highlight objc %}
NameParts *parts = [NameParts new];
NSMutableString *mutableName = [@"John Smith" mutableCopy];
parts.fullName = mutableName;
parts.firstName // => @"John"
[mutableName setString:@"Jack White"];

parts.fullName // => @"Jack White"
parts.firstName // => @"John"
{% endhighlight %}

Previously an object was mutated after being returned; in this case the object is mutated after being passed as a parameter, also resulting in unintended behavior.
The solution is to copy the value:

{% highlight objc %}
- (void)setFullName:(NSString *)fullName {
    _fullName = [fullName copy];
    ...
{% endhighlight %}

When not using a custom setter, you can synthesize the same behavior by marking the property as `copy` instead of `strong` (and it's good form to do so even when you do have a custom setter).
Immutable value classes implement `-copy` to just return self (retained), so there's no cost worth worrying about.
This is true even for classes that don't have mutable counterparts like `NSURL` and `NSNumber`.
You should do this in your own classes.
For [legacy reasons](http://www.cocoabuilder.com/archive/cocoa/65056-what-an-nszone.html) it's actually best to accomplish this by overriding `-copyWithZone:`[^copy-with-zone], like so:

{% highlight objc %}
- (id)copyWithZone:(NSZone *)zone {
    return self; // immutable object
}
{% endhighlight %}

[^copy-with-zone]: `-copy` calls `-copyWithZone:`.

In fact, the behavior of Cocoa's `-copy` method is not obvious.
For classes with immutable variants (such as `NSString`, `NSArray`), `-copy` returns an immutable instance, and `-mutableCopy` returns a mutable instance.
For mutable classes *without* immutable variants (`NSFetchRequest`, `NSAffineTransform`), `-copy` returns a "mutable" copy because that's the only kind of copy; `-mutableCopy` is left unimplemented.
Perhaps we can reconcile this by saying that `-copy` returns *an instance that won't change when some other instance is mutated.*

Don't fear the mutable.
Separating mutable and immutable objects is one of Cocoa's great strengths, while many other libraries have taken much longer to learn of its virtues — particularly relevant in a multi-threaded environment.
Incidentally, not separating mutable and immutable is one of Core Data's great weaknesses, but that's a post for another time.

Also, know your limits.
When you're asked a technical question in an interview or otherwise, please either answer it correctly (great) or say you don't know (no problem, you can look it up); don't say you *do* know but give a wrong answer.
That tends to indicates you *wouldn't* look it up, and would blindly do the wrong thing.
