#!/usr/bin/env crystal run
# -*- coding: utf-8 -*-

class GitPrompt
  SYMBOL = {
    tiger:   "😸",
    yinyang: "☯",
    recycle: "♻",
    hazard:  "☢",
    sun:     "☀",
    smiley:  "☻",
    flag:    "⚑",
    trust:   "♺",
    sword:   "⚔",
    parsley: "☘",
  }

  @status : String
  @branch : String

  def initialize
    @status = git_status
    @branch = git_branch
  end

  def show
    puts prompt
  end

  private def prompt
    return "NO-VC" if @status.empty? && @branch.empty?
    parts = [] of String
    indicator = symbol_for_status
    parts << indicator unless indicator.empty?
    parts << @branch unless @branch.empty?
    parts.join(" ").strip
  end

  private def symbol_for_status
    status = @status
    return SYMBOL[:sun] if status.empty?
    return "\e[1;41m#{SYMBOL[:tiger]}" if clean_worktree?(status) && status.includes?("ahead")
    return "\e[1;41m#{SYMBOL[:sword]}" if status.includes?("behind")
    return SYMBOL[:recycle] if matches?(status, /^A /)
    return SYMBOL[:hazard] if matches?(status, /^ M/)
    return SYMBOL[:sun] if matches?(status, /^\?\?/)
    SYMBOL[:yinyang]
  end

  private def clean_worktree?(status : String)
    !matches?(status, /^A /) && !matches?(status, /^ M/) && !matches?(status, /^\?\?/)
  end

  private def matches?(text : String, pattern : Regex) : Bool
    !!(pattern =~ text)
  end

  private def git_status
    run_git(%w(status --short --branch))
  end

  private def git_branch
    branch = run_git(%w(rev-parse --abbrev-ref HEAD)).strip
    branch == "HEAD" ? "" : branch
  end

  private def run_git(args : Array(String))
    output = IO::Memory.new
    error = IO::Memory.new
    status = Process.run("git", args: args, output: output, error: error)
    status.success? ? output.to_s : ""
  rescue
    ""
  end
end

GitPrompt.new.show
