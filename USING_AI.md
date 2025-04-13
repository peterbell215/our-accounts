# Using Generative AI to write a Rails Application

## Introduction

This document gives my experiences and thoughts on using generative AI to write a Rails application. The application
I am working on is a moderately complex application to track our expenditure across multiple accounts.  This article
captures both my subjective impressions on how Gen AI has helped, but also where it got things wrong.

For this, I have used Gitub Copilot and ChatGPT running inside RubyMine.  I also used the Gen AI tool within Chrome to
understand why things didn't look as I expected.

## The Good

### Writing RSpec tests

I am going to start with the single biggest time saver: writing RSpec tests of all varieties.  In traditional development
I will often spend more time writing and debugging the tests themselves than the code they are testing.

Particularly for system tests, it can be time consuming and really boring to write code that fills out a form, presses
the submit button and checks that the new record has been created, and an appropriate HTML response displayed.

Copilot makes this a much less painful exercise.  The beauty of tests, is that you can look at the generated code, tweak
it and then run it, seeing what you got wrong.  That is not to say that Copilot got it right straight away, but it was
close enough that I could tweak.  This must have saved hours.

That said, you do need to be very careful how you write the prompt.  When I tried:

```text
Create a system test to check the editing of a bank account
```
it suggested throwing away the existing three tests and replacing them with a test that did this.  I had to prompt with:

```text
Add a new system test to check the editing of a bank account.
```

I did find that it wqs best creating a skeleton file for Copilot and asking it to add tests, rather than creating the
RSpec file from scratch.

But even with all that, it genuinely saved me many hours of work.  On top of that, I wrote one test to test for a
possible attack which I probably wouldn't have bethered with, and the test identified a genuine issue.


### Replacing Bootstrap with Pure-CSS

I decided to switch out Bootstrap for Pure-CSS.  Pure-CSS is a simple CSS-only framework that works nicely with the
new Rails ecosystem with Propshaft - no transpiling or complex bundling required.  It was a slighly iterative process
where I asked Gopilot what to change.  This generated a number of errors.  I would feed these back into Copilot which
would suggest how to address.

Copilot didn't get me all the wqy.  Because Propshaft is a new tool, some of the advice was incorrect:

```css
/* app/assets/stylesheets/application.css */

/* This is what Copilot suggested */
@import "css/pure.css";

/* This is what worked */
@import url("purecss/build/pure.css");
```

That said, a key requirement I had was to use the CSS from where yarn had installed it in
`node_modules`.  This required making a small change to the `config/initializers/assets.rb` file:

```ruby
Rails.application.config.assets.paths << Rails.root.join("node_modules")
```

Googling didn't really help me on this one, but Copilot pointed me in the right direction.

### Styling the Application

I don't know about you, but I find CSS a dark art.  It can be very frustrating to get things looking Ok.  Previously,
I would follow advice on StackOverflow.  This would often partially work, so that my quest to get things looking right would
end up a random walk through various StackOverflow suggestions.

Copilot would make sensible suggestions.  When they didn't look quite right, Google's AI tool would provide the extra
bit of help.

### Writing small chunks of JavaScript

Something I wanted the app to do is for dates to be formatted according to the browser's locale.  I asked Copilot how
to do this.  It suggested transmitting the date as an iso8901 string in a data field, and using a short piece of JS
to then reformat and insert it into the HTML.  My Javascript skills are fairly rudimentary, so this no doubt saved
me a couple of hours of Google researching and debugging.

### Regexs

I am somewhat pervase in that I quite enjoy the intellectual challenge of writing regexs.  However, that said, it can
be a real time waster.  Copilot has been very good to quickly taking some examples of how I wanted to accept credit
card numbers and then generating the regex.

## The Bad

### Needing to use Stimulus.js instead of plain JS

Modern Ruby packs a punch: the use of Hotwire and Turbo-Rails allows people like me to build pretty fast and responsive
frontends witbout the need to learn React or Vue.  However, this does mean that Vanilla JS doesn't always work.  Instead,
Rails developers are encouraged to use Stimulus.js to achieve the same thing.  However, because both Hotwire and Stimulus.js
are new, Copilot would suggest Vanilla JS solutions that didn't work.  Even when instructed to use Stimulus.js, instead
it didn't really get it right.

A related issue what that I had written a Stimulus controller that was triggered when a dropdown changed.  This caused
another field to either become visible or hidden.  Locating the fields that needed changing was using Vamilla JS.  The
preferred Stimulus approach is to use targets.  I asked Copilot to rewrite the JS and HTML correspondingly.  While it
got the JS right, the HTML was a complete mess.  As the HTML issues were obvious, it did save me some time, but not
as much as I would have liked.

## The Ugly

The biggest issue I found, was when I asked Copilot to add RSpec system testing using Capybara.  Capybara itself uses
Selenium under the hood and I wanted to run it in a Chrome browser.  So I asked it how to go about building a simple
system test to create a new account.

Although there are numerous good tutorials on how to do this, Copilot suggested a number of things that broke Capybara.
The biggest was two files you need to include in the `spec/rails_helper.rb file`:

```ruby
# What Copilot suggested
require 'capybara/rspec'
require 'selenium-webdriver'

# What was needed
require "capybara/rails"
require "capybara/rspec"
```

Although it's a smnall difference, including the correct files is fundamental to Capybara working out of the box.  With
this mistake, I descended into a nightmare fault-finding session of many hours.  Because all the tutorials have the
correct files, the errors being flagged by Capybara were not known in Stackoverflow and similar forums.  For the same
reason, Copilot was hallucinating ever more complex suggestions of how I should solve the problem based on the error
messages.

In the end, I built a very simple Rails app using an online tutorial.  That worked on first go.  Then I went through
a painstaking exercise of checking for differences between the simple, but working, app and my banking app.  After
an hour I stumbled on this.  Change made, and everything started working!

## Conclusion
