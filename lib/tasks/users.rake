require "io/console"

# Making and mending the people who can sign in.  There is deliberately no sign-up screen and no
# reset-by-email: no SMTP is configured in any environment, and this is a household application on a
# machine its users own, so the shell is the admin interface.
namespace :users do
  # Reads one password without echoing it, where there is a terminal to echo it to.  IO#getpass raises
  # Errno::ENOTTY on a pipe rather than falling back, so a `printf ... | bin/rails users:create` — a
  # perfectly reasonable thing to do from a setup script — would otherwise end in a stack trace.  There
  # is nothing to hide the typing from in that case anyway.
  def prompt(label)
    return $stdin.getpass("#{label}: ") if $stdin.tty?

    print "#{label}: "
    $stdin.gets.to_s.chomp
  end

  # Reads a password twice.  Passwords are prompted for rather than passed as rake arguments on purpose —
  # an argument lands in the shell history and, while the task runs, in `ps`.
  def read_new_password
    password = prompt("Password (at least 12 characters)")
    again    = prompt("And again")

    abort "Those did not match. Nothing has been changed." unless password == again
    abort "Nothing typed. Nothing has been changed." if password.blank?

    password
  end

  def find_user!(task, email_address)
    abort "Usage: bin/rails \"users:#{task}[you@example.com]\"" if email_address.blank?

    User.find_by(email_address: email_address.strip.downcase) ||
      abort("No user with the address #{email_address.inspect}. " \
            "Known: #{User.order(:email_address).pluck(:email_address).join(', ')}")
  end

  desc "Create someone who can sign in"
  task create: :environment do
    print "Email address: "
    email_address = $stdin.gets.to_s.strip

    abort "No address given. Nothing has been created." if email_address.blank?

    if User.exists?(email_address: email_address.downcase)
      abort "#{email_address} already has a login. Use users:change_password to give it a new password."
    end

    user = User.new(email_address: email_address, password: read_new_password)

    unless user.save
      abort "Not created: #{user.errors.full_messages.join('; ')}"
    end

    puts "Created #{user.email_address}."
    puts "Sign in, then set up an authenticator app from the Profile screen — two-factor is off until you do."
  end

  desc "Give someone a new password, for a password that has been forgotten"
  task :change_password, [ :email_address ] => :environment do |_, args|
    user = find_user!("change_password", args[:email_address])
    user.password = read_new_password

    abort "Not changed: #{user.errors.full_messages.join('; ')}" unless user.save

    # The point of a new password is that the old one stops working everywhere, not just here.
    signed_out = user.sessions.destroy_all.count

    puts "Changed the password for #{user.email_address}."
    puts "Signed out #{helpers_pluralize(signed_out, 'device')}." if signed_out.positive?
  end

  desc "Turn two-factor off for someone who has lost their phone"
  task :disable_totp, [ :email_address ] => :environment do |_, args|
    user = find_user!("disable_totp", args[:email_address])

    unless user.otp_secret.present?
      abort "#{user.email_address} has no authenticator app set up, so there is nothing to turn off."
    end

    user.disable_totp!

    puts "Two-factor is off for #{user.email_address}."
    puts "They can now sign in with a password alone, and set it up again from the Profile screen."
  end

  desc "Who has a login here"
  task list: :environment do
    users = User.order(:email_address)
    next puts "Nobody yet. Run bin/rails users:create." if users.none?

    users.each do |user|
      factor = if user.otp_confirmed_at
        "two-factor on since #{user.otp_confirmed_at.to_fs(:short_date)}"
      elsif user.otp_secret
        "two-factor started but never confirmed"
      else
        "password only"
      end

      puts "#{user.email_address.ljust(32)} #{factor}, #{helpers_pluralize(user.sessions.count, 'session')}"
    end
  end

  # pluralize lives in ActionView, which a rake task has no reason to pull in wholesale.
  def helpers_pluralize(count, noun) = "#{count} #{noun}#{'s' unless count == 1}"
end
