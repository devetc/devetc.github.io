---
layout: post
title: "Auto Layout and Views that Wrap"
date:   2014-07-07 11:55:02 -0700
categories: code
tags: cocoa auto-layout
subtitle: Understanding wrapped text and other flowing layouts.
---

Out of the box, wrapped text in a `UILabel` (or `NSTextField` on the Mac) will behave like this when its container is resized:

<!-- http://www.gfycat.com/HeavenlyOrangeAtlanticspadefish -->
<video width="318" height="190" autoplay loop muted="muted" poster="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-default-resize-poster.png">
	<source src="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-default-resize.webm" type="video/webm">
	<source src="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-default-resize.mp4" type="video/mp4">
	<img width="318" height="190" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-default-resize.gif">
</video>

This article explains how to get the following behavior:

<!-- http://www.gfycat.com/UnimportantNervousJackrabbit -->
<video id="gfyVid1" class="gfyVid" width="318" height="236" autoplay="" loop="" muted="muted" style="display: block;" poster="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-dynamic-preferred-max-layout-width-poster.png">
	<source id="webmsource" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-dynamic-preferred-max-layout-width.webm" type="video/webm">
	<source id="mp4source" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-dynamic-preferred-max-layout-width.mp4" type="video/mp4">
	<img width="318" height="236" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-dynamic-preferred-max-layout-width.gif">
</video>


## Why it doesn't "just work"

In auto layout, views have the notion of "intrinsic content size":
A width and height (either, both, or neither) that fits the view well.
The layout system will try to give the view at least this much space with "high" priority, configurable as the view's "compression resistance".

The layout system treats this width and height independently.
For example, if a segmented control's text is long enough that it can't fit horizontally, its intrinsic height will still try to be satisfied.
This works great for views that have some defined size, such as buttons, images, sliders, and small labels.

But views that wrap have more complex behavior: their width and height interact.
They can trade width for height, and vice-versa.

This can't be expressed purely with constraints.
**Proof:**
Consider a simplified model, ignoring word breaking and that complicated text stuff.
We'd like a view to have constant area, i.e. *width* × *height* = *constant*.
Constraints must be of the form *attribute1* = *multiplier* × *attribute2* + *constant* (so the system can provide certain performance guarantees).
There is no way to represent the first equation with the second; hence there is no way to represent wrapping purely with constraints.

We can't leave both width and height as free variables to be solved by the constraint engine.
The simplest approach — and the one that Apple uses — is to fix the width, and leave the height variable (dependent on the label's content).


## Preferred Max Layout Width

Both `UILabel` and `NSTextField` have the `preferredMaxLayoutWidth` property.
If this is non-zero, it's used as the maximum width of the label's intrinsic content size.
When the label has more text than can fit in that width, the label will return a larger value for its intrinsic height.
(If the label has only a little text, the label's intrinsic width can be less than its preferred max layout width.)

On iOS, `UILabel`'s preferred max layout width is set to the width of the label as it appears in the nib (even if it becomes a different size at runtime).

On OS X, `NSTextField` can optionally have its preferred max layout width set to the first size it takes on *after* layout.

If the space available to the label can change, as in the demo at the top, or if the container can be resized (or rotated), you'll need to change the preferred max layout width dynamically.


## Adjusting the Preferred Max Layout Width

To dynamically set `preferredMaxLayoutWidth`, you'll need to override `-[UIView layoutSubviews]` or `-[NSView layout]` of the label's superview.
To get the behavior at the top, set the preferred max layout width to the width available to the label.

The example label has these constraints:

<img width="356" height="178" alt="Label constraints" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/label-constraints.png">

The fixed left and right constraints make it take up all available horizontal space.

*Please don't* hard-code numerical constants in your code.
They'll make your layout overly fragile.
Instead, you can use the layout system to your advantage and do two passes.

The second animation at the top uses the following code in the label's superview:

{% highlight objc %}
- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat availableLabelWidth = self.label.frame.size.width;
    self.label.preferredMaxLayoutWidth = availableLabelWidth;

    [super layoutSubviews];
}
{% endhighlight %}

The first call to `[super layoutSubviews]` will evaluate the constraints on the label (since it's a direct subview) and change its frame accordingly.
At this point the width is useful, but the height is not; the height was set using the label's intrinsic content size, which in turn relied on a preferred max layout width value that is now stale.

Now we know the actual width of the label, we set that as its max layout width.
Internally, this causes the label to invalidate its intrinsic content size; when it's next queried, it will have the accurate height for its current width.
With all layout information in place, we call `[super layoutSubviews]` again.


## Creating your own views that wrap

The [WrapDemo] project contains a view that wraps like `UILabel` / `NSTextField`.
It has a `preferredMaxLayoutWidth` property that the superview sets, and a shared layout method (`-[MyWrappingView enumerateItemRectsForLayoutWidth:usingBlock:]`).
This method is called by both `-intrinsicContentSize` to calculate the size based on the preferred max layout width, and `-layoutSubviews` to position the colored items based on the actual view size.

<!-- http://www.gfycat.com/TidyQuerulousAzurevase -->
<video width="318" height="168" autoplay loop muted="muted" poster="/assets/2014-07-07-auto-layout-and-views-that-wrap/custom-wrapping-view-poster.png">
	<source src="/assets/2014-07-07-auto-layout-and-views-that-wrap/custom-wrapping-view.webm" type="video/webm">
	<source src="/assets/2014-07-07-auto-layout-and-views-that-wrap/custom-wrapping-view.mp4" type="video/mp4">
	<img width="318" height="168" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/custom-wrapping-view.gif">
</video>


## Shrink-Wrapping

Finally, there are times where we'd like to combine wrapping with "shrink to fit" behavior (aka "content hugging").
Instead of fixing the label's leading and trailing space, we can instead add constraints to make it centered and *at least* some distance from the edge.

<img width="356" height="110" alt="Label shrink-wrap constraints" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-label-constraints.png">

Combining this with the above `-layoutSubviews` implementation gives the following behavior:

<!-- http://www.gfycat.com/ArtisticActualBuzzard -->
<video width="318" height="146" autoplay loop muted="muted" poster="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-wrap-buggy-poster.png">
	<source src="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-wrap-buggy.webm" type="video/webm">
	<source src="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-wrap-buggy.mp4" type="video/mp4">
	<img width="318" height="146" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-wrap-buggy.gif">
</video>

The space to the edge is satisfied if it's greater-than-or-equal-to the constant — it only ever pushes the label in, it never pulls it out.
What we want to do is find the width that the label *could* take up, without necessarily taking it all up.

The auto layout API only provides one way to calculate distances: Layout, then measure.
So to find out how wide the label can become, we tell it to become *really* wide (with careful selection of priority), lay it out, measure it, then use the result as the preferred max layout width.
The label's intrinsic size will do the rest.

<!-- http://www.gfycat.com/TornQuarrelsomeEnglishsetter -->
<video width="318" height="148" autoplay loop muted="muted" poster="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-wrap-correct-poster.png">
	<source src="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-wrap-correct.webm" type="video/webm">
	<source src="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-wrap-correct.mp4" type="video/mp4">
	<img width="318" height="148" src="/assets/2014-07-07-auto-layout-and-views-that-wrap/shrink-wrap-correct.gif">
</video>

{% highlight objc %}
- (void)layoutSubviews {
    NSLayoutConstraint *labelAsWideAsPossibleConstraint =
         [NSLayoutConstraint constraintWithItem:self.label
                                      attribute:NSLayoutAttributeWidth
                                      relatedBy:NSLayoutRelationGreaterThanOrEqual
                                         toItem:nil
                                      attribute:0
                                     multiplier:1.0
                                       constant:1e8]; // a big number
    labelAsWideAsPossibleConstraint.priority =
        [self.label contentCompressionResistancePriorityForAxis:UILayoutConstraintAxisHorizontal];
    [self.label addConstraint:labelAsWideAsPossibleConstraint];

    [super layoutSubviews];

    CGFloat availableLabelWidth = self.label.frame.size.width;
    self.label.preferredMaxLayoutWidth = availableLabelWidth;
    [self.label removeConstraint:labelAsWideAsPossibleConstraint];

    [super layoutSubviews];
}
{% endhighlight %}

All these examples are available in the [WrapDemo] project on GitHub.

Thanks to Kevin Cathey for his ongoing help and insights with Auto Layout.

[WrapDemo]: https://github.com/jmah/WrapDemo
