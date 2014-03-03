---
layout: post
title: "Subclassing Delegates"
date: 2014-03-02 22:55:22 -0800
categories: code
tags: cocoa
subtitle: List delegates in your interface, and correctly call super.
---

**tl;dr:** Quickly looking for the right way to subclass delegates?
Jump to the [Summary and Code Snippets](#summary-and-code-snippets).

The delegation pattern is widely used throughout the Cocoa frameworks, for good reason. A delegate customizes another object's behavior in a lightweight way, with less coupling than a subclass.
A single object can be the delegate of several others, so a set of controls presented to the user as a logical group (say, a table and some text fields) can be managed by code that's also kept together.[^massive-view-controller]


## Interface or implementation?

List delegate protocols in the public interface of a class.

Let's consider a chain of three classes: `SpecificViewController : BaseViewController : UIViewController`. `BaseViewController` contains behavior common to several views of our app, and has several subclasses, including `SpecificViewController`. This behavior includes managing a `UITextField`, and so it conforms to the `<UITextFieldDelegate>` protocol.

Objective-C 2.0 added the ability to declare protocols in a class's implementation, like this:

#### BaseViewController.h

{% highlight objc %}
@interface BaseViewController : UIViewController
@end
{% endhighlight %}

#### BaseViewController.m

{% highlight objc %}
#import "BaseViewController.h"
@interface BaseViewController () <UITextFieldDelegate>
@property (nonatomic) IBOutlet UITextField *baseTextField;
@end

@implementation BaseViewController
- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.baseTextField) {
        NSLog(@"%s with %@", __func__, textField.text);
        // ...
    }
}
@end
{% endhighlight %}

At first glance this seems like a good approach, and makes our encapsulation senses tingle with joy.
But it has problems.

Someone else on the team is working on a subclass, `SpecificViewController`, which needs an extra text field. So it also conforms to `<UITextFieldDelegate>`:

#### SpecificViewController.m

{% highlight objc %}
#import "SpecificViewController.h"
@interface SpecificViewController () <UITextFieldDelegate>
@property (nonatomic) IBOutlet UITextField *secondTextField;
@end

@implementation SpecificViewController
- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.secondTextField) {
        // ...
    }
}
@end
{% endhighlight %}

Have you noticed the problem? The behavior attached to `baseTextField` has silently been lost!
The subclass hasn't called super, but calling super would generate a compiler warning, because the protocol was listed in the superclass's private implementation and not public interface.

The solution to this is to **declare delegate protocol conformance in a class's public interface**, and **call super from overridden delegate methods**.
Declaring protocol conformance in the implementation is therefore often inappropriate.

However, there's another complication.


## Forwarding optional methods

Cocoa delegate protocols[^delegate-protocols] have the slightly unusual feature of optional methods.
This speeds up prototyping and development — just implement what you want to use — but interacts with subclassing in a subtle way.

Many delegate methods are `@optional`.
Before calling one, you're responsible for checking whether it's available; the compiler doesn't do any checking.
(It's similar to pointers: the compiler allows you to dereference any address, and your code is responsible for at least ensuring it's not `NULL`.)

We've moved the delegate protocol into the `BaseViewController.h` header file.
Now subclasses can know that the superclass cares about the protocol, so they should forward the methods.
Let's adjust `SpecificViewController.m`:

#### SpecificViewController.m

{% highlight objc %}
@implementation SpecificViewController
- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.secondTextField) {
        // ...
    } else {
        [super textFieldDidEndEditing:textField];
    }
}
@end
{% endhighlight %}

Looks good, works great.
But `secondTextField` needs some more behavior, so it adds another delegate method:

{% highlight objc %}
@implementation SpecificViewController
- (void)textFieldDidEndEditing:(UITextField *)textField {
    // ... as above
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    if (textField == self.secondTextField) {
        return [self someConditionIsMet];
    } else {
        return [super textFieldShouldClear:textField];
    }
}
@end
{% endhighlight %}

We try it out, it works as expected.
But then someone presses the "clear" button in `baseTextField`, and... *crash!*

`-textFieldShouldClear:` is an optional method in `<UITextFieldDelegate>`, so the onus is on the caller to check if it's safe to call — in this case, it's not.
So how can we check?

### 1. Look through the source code of all superclasses.

We see that `BaseViewController` doesn't implement this method, so we can remove the call to super.
But then if it ever adds it, the behavior will be silently lost again!
With this approach, adding or removing a delegate method requires auditing all superclasses and all subclasses — **not a scalable solution**.

Worse: If you miss something, the code will still compile and run.
Everything will likely look fine on the surface, but have a bug lurking below.

### 2. `-respondsToSelector:`, of course

When we implement an object that takes its own delegate, the rule is easy:
Guard all calls to `@optional` methods by `-respondsToSelector:`, like this:

{% highlight objc %}
- (BOOL)canBecomeFirstResponder {
    if ([self.delegate respondsToSelector:@selector(myControlCanBecomeFirstResponder:)]) {
        return [self.delegate myControlCanBecomeFirstResponder:self];
    } else {
        return YES;
    }
}
{% endhighlight %}

Inside `-[SpecificViewController textFieldShouldClear:]` the selector we want to check is the same as the method we're in, so we can just refer to it as `_cmd`.[^_cmd-arg]
Now obviously `[self respondsToSelector:_cmd]` will return true, because we're in that very method right now.
So does `[super respondsToSelector:_cmd]` perform the check we want?

**No.**
The quick-and-dirty translation into English reads, "ask super if it responds to the selector in `_cmd`," but that's wrong and misleading.

We need to think more precisely about what the `super` call *actually* means.
Which is, "call the superclass's implementation of `-respondsToSelector:`, passing it `_cmd`".
Laid out like this, the behavior is clear:
`SpecificViewController` hasn't overridden `-respondsToSelector:`, which means `[self respondsToSelector:]` and `[super respondsToSelector:]` are exactly equivalent, both most likely using `NSObject`'s implementation.

### 3. `+instancesRespondToSelector:`, nice to meet you

This is an oft forgotten `NSObject` method which does exactly as it sounds: performs `-respondsToSelector:`, but at the class level.

So we can do this:

{% highlight objc %}
@implementation SpecificViewController
- (BOOL)textFieldShouldClear:(UITextField *)textField {
    if (textField == self.secondTextField) {
        return [self someConditionIsMet];
    } else if ([BaseViewController instancesRespondToSelector:_cmd]) {
        return [super textFieldShouldClear:textField];
    } else {
        return YES;
    }
}
@end
{% endhighlight %}

**This is correct!**
Note that we also had to hard-code the default value in case the superclass doesn't respond.[^delegate-default-value]

It's ugly to hard-code the superclass in there like that, so how about `[[[self class] superclass] instancesRespondToSelector:_cmd]`?
This *feels like* it should be the same, but it's booby-trapped!
When someone else comes along and declares another subclass, `EvenMoreSpecificViewController : SpecificViewController`, then `[self class]` is `EvenMoreSpecificViewController` and `[[self class] superclass]` is `SpecificViewController`.
That check would succeed, there'd be a call to super (`BaseViewController`), then a crash.
So nope.

It's slightly cleaner is to use the defining class: `[[SpecificViewController superclass] instancesRespondToSelector:_cmd]`.
This adds safety in case a class ever gets split into two, changing the superclass.
But it's still an absolute reference, so the code isn't a nice cut-and-paste snippet.

It'd be nice to have a way to reference the defining class — like the `__FILE__` macro but for the current `@implementation`.
Although there's nothing built-in, it's possible to add with a macro (though less efficiently than one provided by the compiler).
I've done that in the [MyLilHelpers][my-lil-helpers] project, called `_definingClass`.
Using this, we can create a copy-and-paste snippet:
`[[_definingClass superclass] instancesRespondToSelector:_cmd]`.

**Congratulations**, you now know how to subclass a delegate properly!


## Curious UITableViewController behavior

I was initially planning on using `UITableViewController` for this posts's example because it's commonly subclassed, and conforms to both `<UITableViewDataSource>` and `<UITableViewDelegate>`.
I fired up the inquisitive Cocoa developer's best friend, [Hopper Disassembler][hopper-app], to see which of the optional methods it implemented.
To my surprise, I found it's more complicated than that.

`UITableViewController` plays games with `respondsToSelector:`.

{% highlight objc %}
SEL sel = @selector(tableView:heightForRowAtIndexPath:);
[UITableViewController instancesRespondToSelector:sel]; // returns YES
[[[UITableViewController alloc] init] respondsToSelector:sel]; // returns NO!
{% endhighlight %}

Since this is exceptional behavior, I had to choose a different example.

The reason for this is to support the "static data source" mode which can be set up in storyboards[^static-storyboards] with Interface Builder.
`UITableViewController` overrides `-respondsToSelector:` to check if its `_staticDataSource` is nil, and then returns `NO` for a bunch of these methods — but only if they haven't been overridden by a subclass.
As of the iOS 7.0 SDK these methods are:

- `tableView:titleForHeaderInSection:`
- `tableView:titleForFooterInSection:`
- `tableView:heightForHeaderInSection:`
- `tableView:heightForFooterInSection:`
- `tableView:viewForHeaderInSection:`
- `tableView:viewForFooterInSection:`
- `tableView:heightForRowAtIndexPath:`
- `tableView:indentationLevelForRowAtIndexPath:`

There's actually no harm in calling these without a static data source, so the above solutoion still works for `UITableViewController` subclasses.

But what if you *really really* want to know what `UITableViewController` **would** have returned?
If this were [Mike Ash's blog][mike-ash-blog], there'd now be an in-depth examination on using `object_setClass`.
But it's not, so I'll just leave you with this snippet:[^objc-runtime-header]

{% highlight objc %}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    Class orig = object_getClass(self);
    object_setClass(self, [UITableViewController class]);
    BOOL superWouldRespond = [self respondsToSelector:_cmd];
    object_setClass(self, orig);
    // ...
}
{% endhighlight %}

I love the power of Objective-C.
Just to be clear, **don't do this!** Here be dragons.


## Summary and Code Snippets

Specify delegate protocols in the public interface of a class.

{% highlight objc %}
@interface MyViewController : UIViewController <UICollectionViewDataSource>
@end
{% endhighlight %}

If you implement a method from a protocol conformed to by a superclass, call super.

{% highlight objc %}
@interface MyViewControllerSubclass : MyViewController
// adds a section to the collection view
@end

@implementation MyViewControllerSubclass
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    // Optional method. Super may not implement, must check.
    NSInteger baseSections = 1;
    if ([[MyViewControllerSubclass superclass] instancesRespondToSelector:_cmd]) {
        baseSections = [super numberOfSectionsInCollectionView:collectionView];
    }
    return baseSections + 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    // Required method, just call super.
    if (section == (collectionView.numberOfSections - 1)) {
        return 1;
    } else {
        return [super collectionView:collectionView numberOfItemsInSection:section];
    }
}
@end
{% endhighlight %}

With [MyLilHelper][my-lil-helpers]'s `_definingClass` macro, checking super doesn't require specifying the class:

{% highlight objc %}
@implementation MyViewControllerSubclass
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    // Optional method. Super may not implement, must check.
    NSInteger baseSections = 1;
    if ([[_definingClass superclass] instancesRespondToSelector:_cmd]) {
        baseSections = [super numberOfSectionsInCollectionView:collectionView];
    }
    return baseSections + 1;
}
@end
{% endhighlight %}


[my-lil-helpers]: https://github.com/jmah/MyLilHelpers
[hopper-app]: http://www.hopperapp.com/
[mike-ash-blog]:https://mikeash.com/pyblog/

[^massive-view-controller]: Of course, over time a controller can get overgrown with many independent delegate responsibilities. For practical advice on managing this in iOS, see the [objc.io issue on Lighter View Controllers](http://www.objc.io/issue-1/).

[^delegate-protocols]: Delegates have almost all switched over to fully-fledged Objective-C `@protocol`s. In the olden days they were declared as un-implemented categories on `NSObject`, but still called "informal protocols".

[^_cmd-arg]: `_cmd` is like `self`, but references the selector instead of the receiver. See [Objective-C Runtime Programming Guide: Using Hidden Arguments](https://developer.apple.com/library/mac/documentation/cocoa/conceptual/ObjCRuntimeGuide/Articles/ocrtHowMessagingWorks.html#//apple_ref/doc/uid/TP40008048-CH104-TPXREF134).

[^delegate-default-value]: The default for delegate methods that have a return value is usually in the documentation. However some methods, like `-[<UITextFieldDelegate> textFieldShouldReturn:]`, have a complicated set of behavior that's difficult and fragile to replicate if super doesn't respond. I consider this bad API design.

[^static-storyboards]: I don't know why this requires a storyboard instead of a xib. You can drag out a table view controller and a table view, add `dataMode="static"` in the XML, and Xcode will display and edit it fine. But when it's compiled, you'll get *error: Table views with embedded sections and cells are only supported in storyboard documents*. Anyway, this also requires having the nib load the view controller, instead of the (usual) other way around.

[^objc-runtime-header]: You will need to `#import` a particular header for this hackery to compile. If you don't know which one, using this technique will cause you too much trouble.
