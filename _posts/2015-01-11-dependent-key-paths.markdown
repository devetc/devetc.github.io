---
layout: post
title: "Dependent Key Paths"
date: 2015-01-11 19:25:59 -0800
categories: code
tags: cocoa
subtitle: "World first! How to correctly override +keyPathsForValuesAffectingValueForKey:"
---


Much can be said about [key–value observing](kvo) (KVO).
At very least, it's an interesting use of Objective-C's runtime dynamism.
The Apple-provided API is rudimentary; I like to layer something on top that calls a block instead of a method that needs its own dispatch table.
Other libraries like [ReactiveCocoa](https://github.com/ReactiveCocoa/ReactiveCocoa) wrap it in its own conventions.

[kvo]: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/KeyValueObserving/KeyValueObserving.html

But that higher-level stuff is a discussion for another time.
Right now I want to talk about key path dependencies.

Key–value observing supports notifications both directly and indirectly.
Direct notifications, via `[self willChangeValueForKey:@"foo"]` and `[self didChangeValueForKey:@"foo"]`, are automatically wrapped around the corresponding `-setFoo:` setter implementation method (by default).

But some properties don't have direct setters.
The canonical[^fn-names] example for this is this class:

[^fn-names]: and ridden with Anglo-centric cultural assumptions; see [Falsehoods Programmers Believe About Names](http://www.kalzumeus.com/2010/06/17/falsehoods-programmers-believe-about-names/)

{% highlight objc %}
@interface Person : NSObject
@property (copy) NSString *givenName;
@property (copy) NSString *familyName;
@property (readonly) NSString *fullName;
@end

@implementation Person
- (NSString *)fullName {
    return [@[self.givenName, self.familyName] componentsJoinedByString:@" "];
}
@end
{% endhighlight %}

The `fullName` getter depends on `givenName` and `familyName`.
As such it should be annotated as depending on those key paths, so that when an object registers to observe `fullName` it will get a notification when `-setGivenName:` and `-setFamilyName:` are called.

The [+keyPathsForValuesAffectingValueForKey:](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/KeyValueObserving/Articles/KVODependentKeys.html#//apple_ref/doc/uid/20002179-BAJEAIEE) method marks that dependency.
The usual way to specify the above dependency is to implement a method with a special naming convention:

{% highlight objc %}
@implementation Person
+ (NSSet *)keyPathsForValuesAffectingFullName {
    return [NSSet setWithObjects:@"givenName", @"familyName", nil];
}
- (NSString *)fullName { … }
@end
{% endhighlight %}

The default implementation of `+keyPathsForValuesAffectingValueForKey:` dispatches to the method with this name (if any), just as `-valueForKey:@"givenName"` dispatches to `-givenName` and `-setValue: forKey:@"givenName"` dispatches to `-setGivenName:`.


## Dependency helpers

A common case that comes up is:

{% highlight objc %}
@implementation SomeSingleton
- (BOOL)mySetting {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"someKey"];
}
@end
{% endhighlight %}

If user defaults can change separately from this code (and you should probably assume it can), providing correct KVO change notifications can be accomplished by having the singleton observe `NSUserDefaults` with `NSKeyValueObservingOptionPrior`; posting `willChangeValueForKey:@"mySetting"` on the prior callback and `didChangeValueForKey:@"mySetting"` on the post callback.
But this sucks — it's wordy and you pay a (small) performance cost even if `mySetting` isn't observed.

A simpler and more efficient approach is this:

{% highlight objc %}
@implementation SomeSingleton
+ (NSSet *)keyPathsForValuesAffectingMySetting {
    return [NSSet setWithObject:@"$defaults.someKey"];
}
- (BOOL)mySetting { … }
- (NSUserDefaults *)$defaults {
    return [NSUserDefaults standardUserDefaults];
}
@end
{% endhighlight %}

[MyLilKeyPathHelpers][mlkph] adds this shortcut and a couple of others as a category on `NSObject`[^fn-avoid-categories]:

[^fn-avoid-categories]: As a rule I try to avoid categories on framework classes as much as possible. I feel this is one of the rare cases when it's appropriate.

- `$defaults` for `[NSUserDefaults standardUserDefaults]`
- `$app` for the global shared `NSApplication` or `UIApplication` instance (handy as `$app.delegate.someKey`)
- `$classes` as a generic method for the above: for example, `$classes.SomeSingleton.sharedInstance.someKey`

These make it easier to get properties KVO-compliant.
And yes, it's legal to use `$` in identifiers, but be very restrained with it!

[mlkph]: https://github.com/jmah/MyLilKeyPathHelpers


## Specifying dependencies

Instead of implementing the dependency method with a special name, it can be convenient to override the top-level method directly.
For example, each item in [Delicious Library](http://delicious-monster.com/) has properties for fields like title, author, LCCN[^fn-lccn], and notes.
Sorting by these fields sometimes requires custom behavior — for example, sorting by author attempts to massage "Malcolm Gladwell" into "Gladwell, Malcolm".

[^fn-lccn]: [Library of Congress Control Number](http://en.wikipedia.org/wiki/Library_of_Congress_Control_Number)

The way we implement this is to append "ForSorting" to each sort descriptor key.
Then we can provide an `-authorForSorting` method with this custom behavior.
We also override `-valueForKey:` to strip "ForSorting" if the object didn't have a custom implementation, and just return the plain value.

`NSArrayController` observes the keys of its sort descriptors to rearrange (re-sort) when one of the values change.
Accordingly, the "ForSorting" keys needed to be KVO-compliant.
Just as we override the dispatching `-valueForKey:` method, we also overrode `+keyPathsForValuesAffectingValueForKey:` to declare (by default)[^fn-custom-deps] that `authorForSorting` depends on `author`.

[^fn-custom-deps]: Some "ForSorting" values depend on more than one key. For example, `-titleForSorting` depends on both `title` and `dominantLanguageCode`, so "Die Another Day" sorts under "D" while your German copy of "Die Bourne Identität" sorts under "B". Incidentally this causes a lot of user confusion when the language information is not correct.


## Hell is other people's superclasses

[SICP](sicp) made me a convert to the idea of composability.
When building a component on top of another — in this case, writing a class by subclassing `NSObjet` — ideally you can build use on top of it in the same manner the original was constructed.
That is, your class should behave correctly when used as a superclass.

[sicp]: http://en.wikipedia.org/wiki/Structure_and_Interpretation_of_Computer_Programs

Let's see what happens when we extend behavior of our original `Person` class by subclassing.
The `FancyPerson` class provides behavior for "John Smith, Esquire", and `TitledPerson` provides "Mr Smith".

{% highlight objc %}
@interface FancyPerson : Person
@property (copy) NSString *suffix;
@end

@implementation FancyPerson
- (NSString *)fullName {
    return [@[[super fullName], self.suffix] componentsJoinedByString:@", "];
}
@end

@interface TitledPerson : Person
@property (copy) NSString *title;
@end

@implementation TitledPerson
- (NSString *)fullName {
    return [@[self.title, self.familyName] componentsJoinedByString:@" "];
}
@end
{% endhighlight %}

Both of these demonstrate a different behavior:
`FancyPerson` *enhances* the `fullName` method, by calling super and supplementing the return value.
`TitledPerson` *replaces* the `fullName` method, with no call to `[super fullName]`.
Accordingly, `-[FancyPerson fullName]` should declare that it depends on whatever `-[Person fullName]` depends on, plus the `suffix` key.
And `-[TitledPerson fullName]` depends on only `title` and `familyName`, regardless of the superclass.

Let's start with the enhancement case.


### Enhancing key path dependencies

The naive approach has a compile error:

{% highlight objc %}
@implementation FancyPerson
+ (NSSet *)keyPathsForValuesAffectingFullName {
    return [[super keyPathsForValuesAffectingFullName] setByAddingObject:@"suffix"];
    // error: no known class method for selector 'keyPathsForValuesAffectingFullName'
}
@end
{% endhighlight %}

Key path dependencies are typically private, not declared in a class's interface, so the call to super will be a warning or error.
You could declare that you *know* the superclass to implement that method, but that couples to the implementation and may not be correct if `Person` is instead overriding the dispatching method `+keyPathsForValuesAffectingValueForKey:`.

Similar to [subclassing delegates]({% post_url 2014-03-02-subclassing-delegates %}), the correct solution is to use the defining class[^fn-defining-class]:

[^fn-defining-class]: [MyLilKeyPathHelpers](mlkph) provides a helper macro for this called `_definingClass`:

{% highlight objc %}
@implementation FancyPerson
+ (NSSet *)keyPathsForValuesAffectingFullName {
    NSSet *superclassKeys = [[FancyPerson superclass] keyPathsForValuesAffectingValueForKey:@"fullName"];
    return [superclassKeys setByAddingObject:@"suffix"];
}
@end
{% endhighlight %}

This is robust against the superclass's implementation, no matter if it specifies dependencies by implementing the specific method, overriding the dispatching one, or none at all.


### Replacing key path dependencies

Now let's consider `TitledPerson`'s override:

{% highlight objc %}
@implementation TitledPerson
+ (NSSet *)keyPathsForValuesAffectingFullName {
    return [NSSet setWithObjects:@"title", @"familyName", nil];
}
@end
{% endhighlight %}

This is fine.
However there will be a problem if `Person` were to instead override the dispatching method:

{% highlight objc %}
@implementation Person
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    if ([key isEqual:@"fullName"]) { // don't do this
        return [NSSet setWithObjects:@"givenName", @"familyName", nil];
    } else {
        return [super keyPathsForValuesAffectingValueForKey:key];
    }
}
{% endhighlight %}

In this case, the call `[TitledPerson keyPathsForValuesAffectingValueForKey:@"fullName"]` completely ignores the `TitledPerson` override!
Specifically, only when the call to super hits `NSObject`'s implementation of `+keyPathsForValuesAffectingValueForKey:` will the subclass's override of `+keyPathsForValuesAffectingFullName` be called.
You are in a maze of twisty little passages, all alike.

The problem here is the naive implementation of the `+[Person keyPathsForValuesAffectingValueForKey:]` override.


## Correctly overriding +keyPathsForValuesAffectingValueForKey:

It's valid for dependencies to be specified in *either* the dispatching or specific methods, all the way up the inheritance chain.
Correctly overriding `+keyPathsForValuesAffectingValueForKey:` requires some tricky code, which I've wrapped in a function [MLHOverrideKeyPathsForValueAffectingKey](https://github.com/jmah/MyLilKeyPathHelpers/blob/7ed5da8355090b27ceeeb02a20baa7bf7a63eb8a/MyLilKeyPathHelpers/MLHDependentKeyPaths.m#L41) in [MyLilKeyPathHelpers][mlkph].

The `Person` class can use this to correctly override the dispatching method:

{% highlight objc %}
@implementation Person
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    return MLHOverrideKeyPathsForValueAffectingKey(self, [Person class], NO, key, ^(NSSet *superKeyPaths) {
        if ([key isEqual:@"fullName"]) { // or -hasSuffix:, etc.
            return [NSSet setWithObjects:@"givenName", @"familyName", nil];
        } else {
            return superKeyPaths;
        }
    });
}
@end
{% endhighlight %}

With this implementation, calling `[TitledPerson keyPathsForValuesAffectingValueForKey:@"fullName"]` results in a call to `[TitledPerson keyPathsForValuesAffectingFullName]` and that's all.
Accomplishing this unfortunately requires a reimplementation of the method name logic in `NSObject`'s `+keyPathsForValuesAffectingValueForKey:`; I believe this is inescapable.

All the parameters to this function are documented in the [header](https://github.com/jmah/MyLilKeyPathHelpers/blob/7ed5da8355090b27ceeeb02a20baa7bf7a63eb8a/MyLilKeyPathHelpers/MLHDependentKeyPaths.h#L35); take a look.
This same technique could be applied to an override of `-valueForKey:`, though that generally doesn't have the same issues because the dispatch targets (that is, getter methods) *are* declared in a class's public interface.
