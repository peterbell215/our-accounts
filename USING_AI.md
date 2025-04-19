# Using Generative AI to write a Rails Application

## Introduction

This document gives my experiences and thoughts on using generative AI to write a Rails application. The application
I am working on is a side project away from work.  This has the advantage that I can experiment a lot more freely
than when working on production code.

The application is a moderately complex application to track our house expenditure across multiple accounts.  This article
captures both my subjective impressions on how Gen AI has helped, but also where it got things wrong.  My goto for
writing side projects is Ruby-on-Rails in the latest version V8.  I tend to use RoR's features such as Turbo and
Stimulus to support simple UI implementation, rather than writing the UI in one of the many JS frameworks.  I recently
switched from using Bootstrap to using Pure-CSS.  Again, this works well with the RoR philosophy of avoiding complex JS
build configurations.  Also for me, as a CSS novice, its a lot easier to work out what is going on.

For this project, I started with Github Copilot and ChatGPT 4o running inside RubyMine.  I also used the Gen AI tool
within Chrome to understand why things didn't look as I expected.

As I was writing this, Gemini Pro 2.5 landed.  There has been a lot of buzz around it, so I have also given it a whirl.
I document this in the 2nd section of this report.  

# Github Copilot within JetBrains Rubymine using the ChatGPT 4o

## The Good

### Writing RSpec tests

I am going to start with the single biggest time saver: writing RSpec tests of all varieties.  In traditional development
I will often spend more time writing and debugging the tests themselves than the code they are testing.

Particularly for system tests, it can be time consuming and really boring to write code that fills out a form, presses
the submit button and checks that the new record has been created, and an appropriate HTML response displayed.

Copilot makes this a much less painful exercise.  The beauty of the generated tests is that you can look at the
generated code, tweak  it and then run it, seeing what you got wrong.  That is not to say that Copilot got it right
straight away, but it was close enough that I could tweak.  This must have saved hours.

That said, you do need to be very careful how you write the prompt.  When I tried:

```text
Create a system test to check the editing of a bank account
```
it suggested throwing away the existing three tests and replacing them with a test that did this.  I had to prompt with:

```text
Add a new system test to check the editing of a bank account.
```

I did find that it was best creating a skeleton file for Copilot and asking it to add tests, rather than creating the
RSpec file from scratch.

But even with all that, it genuinely saved me many hours of work.  On top of that, I wrote one test to test for a
possible attack which I probably wouldn't have bethered with, and the test identified a genuine issue.

### Copying what I had implemented for one set of models for another

Gen AI at its best.  Having created a reasonably sound structure of how Accounts and rendered including system
tests, I was able to ask Copilot to create a similar set of views and system tests for Categories. I am sure we have
all experienced the boring process of copying and pasting code from one view directory to another, then having to
make tweaks.  Likewise for the RSpec tests.

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

# Google Gemini Pro 2.5

## How to use Gemini Pro 2.5

As mentioned above, my preferred IDE for development is JetBrain's RubyMine.  The current Github Copilot plugin does
allow users to use different LLMs.  However, although Github Copilot does now support Gemini Pro but not in JetBrains.
Google does provide a plug-in for JetBrains that does use the Pro LLM.  However its integration with JetBrains is much
less powerful.  Copilot provides for each code segment some buttons to easily insert the recommendations into
the appropriate file.  Particularly powerful here, is that it provides it as a side by side comparison (similar to
JetBrain's file history comparison feature).  This allows you to understand the individual changes, and agree or
disagree with them.

Google provide a plugin for JetBrains IDEs.  However, its integration into the JetBrains eco-system is much poorer.
I learnt, that I needed to ask Gemini to produce the results as a diff file.  I could then use the Git
Apply Patch to see the diffs and apply them in a selective way.

I decided to switch at this point to VSCode, where the integration of Gemini is much better.  My gut feeling is that
if you want to make heavy use of LLMs in general, and Gemini Pro specifically, you are probably better using VSCode.

## Implementing a drag and drop UI

Having read about the strength of Google Gemini Pro 2.5, I started immediately with a bigger challenge.  I asked it to
recast the form that defines how the app parses CSV files downloaded from various financial institutions.  Originally,
this was a simple form where I provided a form with text fields where users could enter either the CSV fieldname or
column index.  Users could either enter the column index as a number, or as a text.  I wanted to add an extra form to
the page that would allow a user to load a sample CSV file.  It would show the headers/first row.  These could be
then picked up and dropped into the main form.

... insert original form vs new form ...

Gemini Pro came up with a credible version of what I wanted in a first go.  If I had tried to do this myself, my best
guess is that it would have taken at least a week.  By contrast, Gemini Pro needed a few minutes.  Its result where
close to what we needed.

That said, Gemini Pro made a few wrong turns.  Also, it both manages to sometimes overcomplicate the code, and also to
take a more simplisitc approach.

Also, Rails has quite strict conventions on what belongs in the controller, in the view and the model (the concept of
thin controllers versus fat models). Gemini Pro put everthing in the controller - some of which should have been made
methods on the model.

In the RoR world, there are two ways that you can dynamically change the contents of a page: turbo-forms and
turbo-streams.  The first is much easier to use (no JS needed), while the second is great for async changes, but more
complex (particularly, if you want push notifications).  Gemini Pro chose the latter.  After I got the first version
working, I went through a few iterations to simplify the code by switching to the former.

The other side is that my model for defining ImportColumnsDefinition includes a number of model fields to map specific
CSV fields into my Transaction record.  Examples include date_column, credit_column, and account_column.  The way these
column fields work, is fairly similar.  In my code, I have a constant CSV_HEADERS that identifies all these fields, and
I use loops to implement the same functionality in the forms across multiple fields.  By contrast, Gemini will write
the same code 10 times, rather than constructing a single loop.

Another issue was that RoR minimises the need for JS.  Gemini Pro implemented in JS some items that could have been done
in a simpler way through standard tags in the HTML.erb file.

## Expanding the UI to provide interaction between different elements of the form

All of the financial institutions I use provide a method for downloading a CSV file of transactions.  However, these
vary quite significantly.  One important difference is whether the first line of the CSV file is a header or not.
To support this, I had a checkbox in the main form that flags whether the CSV file has this header.

Now the CSV importer Gem is able to sometimes detect whether the CSV is inconsistent implying no header.  In this case
I want to drag and drop column numbers.  If the CSV file does contain a header, I want to drag and drop the column
name defined in the header.

So I wanted to make two changes to the form.  If the importer detected that the file did not contain a header, it
should automatically uncheck the CSV header checkbox.  I wrote a fairly detailed prompt, hoping that Gemini would
work out all the changes required to address this.  The generated code was a complete disaster.  However, what worked
pretty well, was breaking the problem down into a set of steps, and prompting Gemini to modify specific files in a
more specific way:

* Surface the results of the CSV header analysis in the class method that analyses the CSV file.
* Update rendering code for the view that provides the analysis results to include a data element with the conclusion
* Update the Stimulus controller to respond to an event of the turbo-form being reloaded, examine the corresponding
  data element and then update the checkbox status accordingly.

Gemini Pro helped with all 3.  I would say that particularly for changes to the Stimulus controller, Gemini Pro made
some initial suggestions, but I ended up doing much of the coding by hand.

## System Tests for the new functionality

Once the code was working reasonably well, I wanted to build a system test.  Gemini Pro did a reasonable job of
generating a test script.  While not perfect it saved me several hours of cumbersome coding.  I did still need to
polish it.  That said, certainly a significant time saving.


Some of the coding was a bit cumbersome.  What I would expect a slightly inexperienced developer to produce.  Not a big
issue.

It did make a couple of genuine mistakes, firstly it included a JS module, but didn't point out that it needed to be
added to the library.  Secondly, and probably more importantly, it placed a key data field required by its Javascript
onto the wrong HTML element.  Gemini Pro was not able to identify the problem correctly, and I was back to old-fashioned
debugging.

# Commit Messages

Obviously, this is a single person side project, so getting my Git commits right is nowhere near as important in true
team environment.  That said, both VSCode and GitKraken (I use this in preference to JetBrain's inbuilt Git commit
tooling) offer a magic button to generate the commit message.  I have been impressed with the quality of the messages
produced.  I now always press the button to get AI to generate the commit message.  Only once have I had to delete
and start again. 95% of the time I use the message as suggested with no changes.

# Conclusion

LLMs can provide some real time saving for development.  That said, my experience is that they are not yet a panacea.
I would treat an LLM such as Gemini Pro as an intelligent but not necessarily experienced developer.  Give it a targeted
task, and it will make some sensible suggestions.  Treat these like PRs, and review carefully.  Sometimes, tell it
to make changes to its suggested approach.  In other cases, you might be better doing it yourself.

