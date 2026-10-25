# Security and privacy

MyBaby keeps a baby's log on the parent's iPhone and, if they turn it on, in their own iCloud account,
end-to-end encrypted. There are no MyBaby servers, accounts, analytics or ads. This code is public so
anyone can check those claims for themselves.

## Reporting a problem

If you find a way that MyBaby could expose a family's data, or that the app does something the
[privacy policy](docs/privacy.html) says it doesn't, please email
**mybaby@manhattin.com** with:

- what you found and where in the code (file and line, if you can),
- how to reproduce it, and
- the iOS and MyBaby versions you used.

Please don't open a public issue for a security or privacy problem. You'll get a reply within a few days,
and a fix will be released as quickly as possible. With your permission, you'll be credited in the
release notes.

## What's in scope

- Anything that sends a family's data off the device, other than to the parent's own iCloud through Apple's
  CloudKit, or to a partner they invited.
- Data that is shared with a partner but shouldn't be (for example, a parent's private care page).
- Data that isn't end-to-end encrypted in iCloud when it should be.
- The Face ID lock on the care page being bypassed.
- Widgets, the Apple Watch, Siri or notifications showing more than they should.

Problems in iOS, iCloud or CloudKit themselves should be reported to
[Apple](https://security.apple.com).
