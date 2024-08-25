# UPS

[![Test Matrix](https://github.com/disruptek/ups/workflows/CI/badge.svg)](https://github.com/disruptek/ups/actions?query=workflow%3ACI)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/disruptek/ups?style=flat)](https://github.com/disruptek/ups/releases/latest)
![Minimum supported Nim version](https://img.shields.io/badge/nim-2.0.10%2B-informational?style=flat&logo=nim)
[![License](https://img.shields.io/github/license/disruptek/ups?style=flat)](#license)
[![buy me a coffee](https://img.shields.io/badge/donate-buy%20me%20a%20coffee-orange.svg)](https://www.buymeacoffee.com/disruptek)

UPS is a package handler, obviously.

## Seriously?  Yet another package manager?

No, don't be ridiculous.  This is a library for package handling.

## What's the point of that?

The idea is to create a library of basic Nim package handling machinery that
can serve to illustrate/implement best practices, and which can eventually
be used more broadly to unify the community's package management efforts.

## But, isn't that what Nimph is?

Nimph's dependencies can be rather onerous -- I personally want to be able to
perform basic package operations in other code without having to specify a
dependency on Nimterop and libgit2. Similarly, this allows that use to help
improve Nimph as well.

## Okay, so, like, it runs Nimble?

No, don't be ridiculous.  The initial scope we're targeting looks like this:

- a proper **Version** type with https://semver.org/ semantics
- a **Release** type that references **Version** or tag combined with an **Operator**
- additional **`^`**, **`*`**, and **`~`** operators as used in Nimph
- a **Package** type that represents published code with Nimble specifications
- **Requirement** parsing that connects a **Package** specification to a **Release**
- a **Project** type that represents code available for local `import`
- **Dependency** resolution via multiple **Package** or **Project** values and multiple **Requirement** instances
- **Lockfiles** that declare these type-relations in a single data-structure
- Nim `.cfg` parsing, editing, and writing with/without compiler code

## Ahh, that makes a lot of sense!  Thanks for sharing.

You're welcome, buddy.  Enjoy.  😘

## Documentation

This code is in an active state of development and the API is likely to change
frequently; use the tagged releases to protect yourself accordingly.

[The documentation is built during the CI process and hosted on
GitHub.](https://disruptek.github.io/ups/ups.html)

## License
MIT
