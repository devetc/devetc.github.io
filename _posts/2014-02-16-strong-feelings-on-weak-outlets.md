---
layout: post
title:  "Strong Feelings on Weak Outlets"
date:   2014-02-16 11:02:56 -0800
categories: code
tags: cocoa interface-builder memory-management
subtitle: Declare outlets as strong.
---

There are mixed opinions on whether `IBOutlet` properties should be strong or weak.
Apple themselves changed their recommendation with iOS 5.
However their advice right now is bad — or at least poorly reasoned.
The rest of the Cocoa guidelines and my own experience both lead me to the opposite conclusion: **declare outlets as strong**.

To clarify, I'm talking about outlets from controllers to views — outlets on "File's Owner", often a `UIViewController`, `NSViewController`, or `NSWindowController` instance.
(And yes, "owner" does imply "strong".)
Outlets from views to controllers or other views — for example a table view subclass adding an `awesomeSource` — should be weak.

Tedious analysis follows.

## Apple's reasons

Apple documents their recommendations in the [Resource Programming Guide: Nib Files][adc-nibs]:

> Outlets should generally be `weak`, except for those from File’s Owner to top-level objects in a nib file (or, in iOS, a storyboard scene) which should be `strong`.
> Outlets that you create should therefore typically be `weak`, because:
>
> - Outlets that you create to subviews of a view controller’s view or a window controller’s window, for example, are arbitrary references between objects that do not imply ownership.
> - The strong outlets are frequently specified by framework classes (for example, `UIViewController`’s view outlet, or `NSWindowController`’s window outlet).
>
> <pre><code>@property (weak) IBOutlet MyView *viewContainerSubview;
> @property (strong) IBOutlet MyOtherClass *topLevelObject;
> </code></pre>

But there are caveats to using weak:

> Outlets should be changed to `strong` when the outlet should be considered to own the referenced object:
>
> - As indicated previously, this is often the case with File’s Owner—top level objects in a nib file are frequently considered to be owned by the File’s Owner.
> - You may in some situations need an object from a nib file to exist outside of its original container. For example, you might have an outlet for a view that can be temporarily removed from its initial view hierarchy and must therefore be maintained independently.

To summarize, the documentation says, "use weak when you can, but it doesn't always work".
If you do use weak references in the above cases, it will sometimes work (both `UIViewController` and `NSViewController` actually *do* retain the top-level objects of a nib, but it's undocumented), and sometimes fail (removing a view from its superview, if that was the last strong reference).
Oh, and remember to change them from `weak` to `strong` if the layout of the nib changes, or if you start doing something different with the connected objects.
And remember to change them from `strong` back to `weak` because… well, **why exactly**?

Each of the above reasons sounds like, "some objects already have a retaining reference, so they **shouldn't have** another", which is an argument against reference counting in favor of `malloc`/`free` semantics.

Consider a simple case:

    @interface ChooseOne : NSObject
    @property (nonatomic, strong) NSArray *options; // @[@"one", @"two", @"three"]
    @property (nonatomic, ?) NSString *selectedOption;
    @end

The `options` property indirectly holds a strong reference to all the options, so by the nib doc's first reason `selectedOption` should be declared `weak`.
That could work, but it's overly fragile:

1. If `selectedOption` is set before `options`, the value may or may not be nil.
Even worse, the outcome could depend on the compiler's optimization setting:
Everything could look fine in Debug, but fail in Release!
2. There are values that compare equal but aren't identical, such that `[choice.options containsObject:opt]` is true, but when stored in `selectedOption` would silently be lost.

The sane storage specifier for `selectedOption` is at least `strong` (`copy` is even more appropriate).

The docs also convey the feeling that `weak` is an optimization. With my memory-management goggles on, this is how I read the above:

- Outlets that are connected to subviews are already retained by the top-level `view` (or `window`) outlet, so they **shouldn't bother** with that retain/release stuff.
- The outlets that do need to do these "heavy-weight" retain/release calls are typically provided by the system.

This is misleading, because accessing a `weak` property is many times slower than a `strong` one!
All that's needed to access a `strong, nonatomic` property is just to read and return the pointer value.[^objc-accessors]
Accessing a `weak, nonatomic` property requires first testing that the object hasn't been marked as deallocated, then retaining and autoreleasing the value (otherwise the returned pointer may turn invalid at any time); and each part of this access requires locking.[^objc-loadWeak]

The only reason in support of `weak` outlets is that they don't require explicit clean-up when releasing the top-level view.
But unloading the top-level view turned out to be difficult to get correct, difficult to test, and **very difficult** to keep correct as the code changes.
So Apple very practically decided to stop doing it as of iOS 6.[^wwdc-viewDidUnload]

## Curiouser

At some point in 2011[^adc-nibs-revision-history], the guidelines for iOS was changed from `strong` to `weak`.
I'd really like to know the history of this, because the reasons stated now were just as valid then.
Perhaps there's some unstated reason?

> Prior to ARC, the rules for managing nib objects are different from those described above. How you manage the objects depends on the platform and on the memory model in use. Whichever platform you develop for, you should define outlets using the Objective-C declared properties feature.
>
> [...]
>
> - For iOS, you should use:
> <pre><code>@property (nonatomic, retain) IBOutlet UserInterfaceElementClass *anOutlet;</code></pre>
>
> - For OS X, you should use:
> <pre><code>@property (assign) IBOutlet UserInterfaceElementClass *anOutlet;</code></pre>

## Share Your Thoughts

Do you have strong feelings on this?
Am I missing something mind-numbingly obvious?
Shoot a Twitter-gram to the germinal [@dev_etc](https://twitter.com/dev_etc), or an App.net-o-gram to [@jmah](https://alpha.app.net/jmah)


[adc-nibs]: https://developer.apple.com/library/mac/documentation/cocoa/conceptual/loadingresources/CocoaNibs/CocoaNibs.html

[^objc-accessors]: See the [objc-accessors.mm source file](http://www.opensource.apple.com/source/objc4/objc4-551.1/runtime/Accessors.subproj/objc-accessors.mm)
[^objc-loadWeak]: See `objc_loadWeak` in clang's [Automatic Reference Counting documentation](http://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-runtime-objc-loadweak).[^wwdc-viewDidUnload]: See [WWDC 2012](https://developer.apple.com/videos/wwdc/2012/) Session 200: "What's New in Cocoa Touch", 00:18:00 in.
[^adc-nibs-revision-history]: Actually 2011-10-12, thanks to the [revision history](https://developer.apple.com/library/mac/documentation/cocoa/conceptual/loadingresources/RevisionHistory.html#//apple_ref/doc/uid/20001604-CJBGIAGF)
