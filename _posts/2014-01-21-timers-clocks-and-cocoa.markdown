---
layout: post
title:  "Timers, Clocks, and Cocoa"
date:   2014-01-21 14:03:49 -0700
categories: code
tags: cocoa date-and-time timer
subtitle: Read me before using NSTimer.
---

Time is a complicated thing (cf. relativity), yet it's a vital part of programs interacting with the world.
In casual conversation we usually speak as if there is one value called "the time", which we can read from "the clock".
But because "the clock" can be changed by both the user and automatic time setting, we realize things  unfortunately cannot be not that simple.
There are, in fact, multiple clocks.
At first glance they all look like they run at the same rate and so it doesn't appear important to choose one over another, but they have quite different behaviors and inevitably diverge over time.

Choosing the wrong clock can make your software behave unexpectedly, and possibly crash.
A lot of code makes incorrect assumptions about the real-time clock, and takes non-sensical actions if a time difference is negative.
But because clock changes are uncommon, these bugs can appear to be [Heisenbugs](http://en.wikipedia.org/wiki/Heisenbug).

As an application developer, these are the most useful clocks in practice[^cpu-time]:
 
1. The **real-time clock**, usually accessed in Cocoa via `NSDate`.[^unix-realtime]
This is the system's best guess of [coordinated universal time][wiki-utc] (UTC).
The user can change this clock arbitrarily, and the NTP (Network Time Protocol) serivce also makes changes as it tries to keep it in sync with an external reference.
While the value of this clock typically increases by 1 second per real second, at times it runs faster or slower, and makes discontinuous jumps both forwards and backwards.[^ntp-clock-changing]

2. **Monotonic time** is basically a counter that gets incremented when a physical timer signals the CPU via a timer interrupt.
On Mac OS X and iOS, the counter value is returned from `mach_absolute_time()`, and the number of counts per second is returned by `mach_timebase_info()`.[^mach-absolute-time-units]
Several functions include the conversion to seconds: `-[NSProcessInfo systemUptime]`, `CACurrentMediaTime()`, and others.
The particular value of this counter isn't really useful, but the difference between two readings tells you how much time has elapsed, regardless of any changes to the real-time clock.
This is useful for measuring throughput, or processing speed, of some operation — numbers like "frames per second".
However since the CPU increments this counter, *the monotonic clock stops when the CPU is powered down*.

3. **Boot time**, which is like monotomic time but does not pause when the system goes to sleep.
This value is reported by the `uptime` tool.

`NSTimer` uses monotonic time. This means it pauses when the system goes to sleep, which happens unpredictably and opportunistically on iOS!
This makes `NSTimer` **incorrect for timeouts and timing** involving anything external — from waiting for a server response to timing the cooking of an egg.
`NSTimer` is only appropriate if the process being timed is confined to the system — such as your app waiting for a result from the kernel, or another app.

## Pick your clock

<iframe width="640" height="360" src="//www.youtube-nocookie.com/embed/ZRM8mq-ZSO0?rel=0" frameborder="0" allowfullscreen></iframe>

This chart lays out how the clock values change over time in the above video:

![Clock values over time](/assets/MyLilTimers-clock-values-over-time.svg)

For measuring durations without interference from real-time clock changes or system sleep, **you need to use boot time**. Unfortunately this is unreasonably difficult with Cocoa, so I wrote something: [MyLilTimer](https://github.com/jmah/MyLilTimer) has an interface similar to `NSTimer`, but with the option of the three behaviors above. Because iOS suspends apps in the background, an app can often be notified of the firing of a timer significantly after it was scheduled to fire. The `-timeSinceFireDate` method returns that duration, using the clock selected by the timer.

To make matters worse, iOS devices don't go to sleep when plugged in — including when running an app from Xcode. So using `NSTimer` can appear to act like using boot time, until you run with the device unplugged!

The Cocoa frameworks do not offer any way to be notified of these time discontinuities in general. UIKit offers `UIApplicationSignificantTimeChangeNotification` which fires when the real-time clock changes (and a couple of other cases useful for calendar-type apps), but not when waking from sleep. On the Mac there is `NSWorkspaceDidWakeNotification`,[^sleep-wake] but there is no (public) counterpart for iOS.

`dispatch_after` (and a timer `dispatch_source`) offers both the monotonic and real-time clock, depending on how the `dispatch_time` object is created. The boot time behavior is a combination of the two — run continuously during system clock changes (like the monotonic clock), and stay running during system sleep (like the real-time clock) — so we should be able to build our own. The [libdispatch source][libdispatch-source.c] observes the `HOST_NOTIFY_CALENDAR_CHANGE` Mach notification to reschedule real-time clock timers. The only form of documentation appears to be comments in the [kernel source][kern-clock.c], which indeed indicates it's sent when the real-time clock changes, as well as when the system is woken:

	/*
	 *	clock_initialize_calendar:
	 *
	 *	Set the calendar and related clocks
	 *	from the platform clock at boot or
	 *	wake event.
	 *
	 *	Also sends host notifications.
	 */
	
	/*
	 *	clock_set_calendar_microtime:
	 *
	 *	Sets the current calendar value by
	 *	recalculating the epoch and offset
	 *	from the system clock.
	 *
	 *	Also adjusts the boottime to keep the
	 *	value consistent, writes the new
	 *	calendar value to the platform clock,
	 *	and sends calendar change notifications.
	 */

However it does *not* mention how far this behavior has existed, so older OS versions potentially don't do the same thing (it works back to at least iOS 6). It is used in several place though, including by the [power management daemon][pmconfigd.c] to re-sync the battery's time remaining.

[MyLilTimer](https://github.com/jmah/MyLilTimer) observes this one notification, checks the value of the corresponding clock, and resets an internal `NSTimer` to the new expiry date. Give it a go!


[wiki-utc]: http://en.wikipedia.org/wiki/UTC
[wiki-cpu-time]: http://en.wikipedia.org/wiki/CPU_time
[libdispatch-source.c]: http://opensource.apple.com/source/libdispatch/libdispatch-339.1.9/src/source.c
[kern-clock.c]: http://www.opensource.apple.com/source/xnu/xnu-2422.1.72/osfmk/kern/clock.c
[pmconfigd.c]: http://opensource.apple.com/source/PowerManagement/PowerManagement-420.1.20/pmconfigd/pmconfigd.c

[^cpu-time]: There is also [**CPU time**][wiki-cpu-time], which is the time that a single CPU has been dedicated to a process. This is the "user" number when using `time` on the command-line. When a process runs for 1 second usilizing 75% of 4 cores, the CPU time is `1 * 0.75 * 4 = 3 core • seconds`. Since this has different units (not seconds), it is not a clock.

[^unix-realtime]: and Unix via `gettimeofday`, or `clock_gettime` with `CLOCK_REALTIME`.

[^ntp-clock-changing]: When NTP synchronizes, it changes the system clock, [either instantly or slowly depending on the difference](http://www.ntp.org/ntpfaq/NTP-s-algo.htm#Q-CLOCK-DISCIPLINE).

[^mach-absolute-time-units]: [Technical Q&A QA1398: Mach Absolute Time Units](https://developer.apple.com/library/mac/qa/qa1398/_index.html)

[^sleep-wake]: [Technical Q&A QA1340: Registering and unregistering for sleep and wake notifications](https://developer.apple.com/library/mac/qa/qa1340/_index.html)