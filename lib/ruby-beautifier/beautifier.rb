class RubyBeautifier
# STANDALONE START
    def setup_parser(str, debug=false)
      @string = str
      @pos = 0
      @memoizations = Hash.new { |h,k| h[k] = {} }
      @result = nil
      @failed_rule = nil
      @failing_rule_offset = -1

      setup_foreign_grammar
    end

    # This is distinct from setup_parser so that a standalone parser
    # can redefine #initialize and still have access to the proper
    # parser setup code.
    #
    def initialize(str, debug=false)
      setup_parser(str, debug)
    end

    attr_reader :string
    attr_reader :result, :failing_rule_offset
    attr_accessor :pos

    # STANDALONE START
    def current_column(target=pos)
      if c = string.rindex("\n", target-1)
        return target - c - 1
      end

      target + 1
    end

    def current_line(target=pos)
      cur_offset = 0
      cur_line = 0

      string.each_line do |line|
        cur_line += 1
        cur_offset += line.size
        return cur_line if cur_offset >= target
      end

      -1
    end

    def lines
      lines = []
      string.each_line { |l| lines << l }
      lines
    end

    #

    def get_text(start)
      @string[start..@pos-1]
    end

    def show_pos
      width = 10
      if @pos < width
        "#{@pos} (\"#{@string[0,@pos]}\" @ \"#{@string[@pos,width]}\")"
      else
        "#{@pos} (\"... #{@string[@pos - width, width]}\" @ \"#{@string[@pos,width]}\")"
      end
    end

    def failure_info
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        "line #{l}, column #{c}: failed rule '#{info.name}' = '#{info.rendered}'"
      else
        "line #{l}, column #{c}: failed rule '#{@failed_rule}'"
      end
    end

    def failure_caret
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      line = lines[l-1]
      "#{line}\n#{' ' * (c - 1)}^"
    end

    def failure_character
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset
      lines[l-1][c-1, 1]
    end

    def failure_oneline
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      char = lines[l-1][c-1, 1]

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        "@#{l}:#{c} failed rule '#{info.name}', got '#{char}'"
      else
        "@#{l}:#{c} failed rule '#{@failed_rule}', got '#{char}'"
      end
    end

    class ParseError < RuntimeError
    end

    def raise_error
      raise ParseError, failure_oneline
    end

    def show_error(io=STDOUT)
      error_pos = @failing_rule_offset
      line_no = current_line(error_pos)
      col_no = current_column(error_pos)

      io.puts "On line #{line_no}, column #{col_no}:"

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        io.puts "Failed to match '#{info.rendered}' (rule '#{info.name}')"
      else
        io.puts "Failed to match rule '#{@failed_rule}'"
      end

      io.puts "Got: #{string[error_pos,1].inspect}"
      line = lines[line_no-1]
      io.puts "=> #{line}"
      io.print(" " * (col_no + 3))
      io.puts "^"
    end

    def set_failed_rule(name)
      if @pos > @failing_rule_offset
        @failed_rule = name
        @failing_rule_offset = @pos
      end
    end

    attr_reader :failed_rule

    def match_string(str)
      len = str.size
      if @string[pos,len] == str
        @pos += len
        return str
      end

      return nil
    end

    def scan(reg)
      if m = reg.match(@string[@pos..-1])
        width = m.end(0)
        @pos += width
        return true
      end

      return nil
    end

    if "".respond_to? :getbyte
      def get_byte
        if @pos >= @string.size
          return nil
        end

        s = @string.getbyte @pos
        @pos += 1
        s
      end
    else
      def get_byte
        if @pos >= @string.size
          return nil
        end

        s = @string[@pos]
        @pos += 1
        s
      end
    end

    def parse(rule=nil)
      if !rule
        _root ? true : false
      else
        # This is not shared with code_generator.rb so this can be standalone
        method = rule.gsub("-","_hyphen_")
        __send__("_#{method}") ? true : false
      end
    end

    class LeftRecursive
      def initialize(detected=false)
        @detected = detected
      end

      attr_accessor :detected
    end

    class MemoEntry
      def initialize(ans, pos)
        @ans = ans
        @pos = pos
        @uses = 1
        @result = nil
      end

      attr_reader :ans, :pos, :uses, :result

      def inc!
        @uses += 1
      end

      def move!(ans, pos, result)
        @ans = ans
        @pos = pos
        @result = result
      end
    end

    def external_invoke(other, rule, *args)
      old_pos = @pos
      old_string = @string

      @pos = other.pos
      @string = other.string

      begin
        if val = __send__(rule, *args)
          other.pos = @pos
        else
          other.set_failed_rule "#{self.class}##{rule}"
        end
        val
      ensure
        @pos = old_pos
        @string = old_string
      end
    end

    def apply(rule)
      if m = @memoizations[rule][@pos]
        m.inc!

        prev = @pos
        @pos = m.pos
        if m.ans.kind_of? LeftRecursive
          m.ans.detected = true
          return nil
        end

        @result = m.result

        return m.ans
      else
        lr = LeftRecursive.new(false)
        m = MemoEntry.new(lr, @pos)
        @memoizations[rule][@pos] = m
        start_pos = @pos

        ans = __send__ rule

        m.move! ans, @pos, @result

        # Don't bother trying to grow the left recursion
        # if it's failing straight away (thus there is no seed)
        if ans and lr.detected
          return grow_lr(rule, start_pos, m)
        else
          return ans
        end

        return ans
      end
    end

    def grow_lr(rule, start_pos, m)
      while true
        @pos = start_pos
        @result = m.result

        ans = __send__ rule
        return nil unless ans

        break if @pos <= m.pos

        m.move! ans, @pos, @result
      end

      @result = m.result
      @pos = m.pos
      return m.ans
    end

    class RuleInfo
      def initialize(name, rendered)
        @name = name
        @rendered = rendered
      end

      attr_reader :name, :rendered
    end

    def self.rule_info(name, rendered)
      RuleInfo.new(name, rendered)
    end

    #


  def initialize(str, debug=false)
    setup_parser(str, debug)
    @tabs = 0
    @space = "  "
    @processed = ""
    @str_token = ""
  end

  attr_accessor :tabs, :space
  attr_accessor :processed



  def setup_foreign_grammar; end

  # space = " "
  def _space
    _tmp = match_string(" ")
    set_failed_rule :_space unless _tmp
    return _tmp
  end

  # tab = "\t"
  def _tab
    _tmp = match_string("\t")
    set_failed_rule :_tab unless _tmp
    return _tmp
  end

  # - = (space | tab)*
  def __hyphen_
    while true

    _save1 = self.pos
    while true # choice
    _tmp = apply(:_space)
    break if _tmp
    self.pos = _save1
    _tmp = apply(:_tab)
    break if _tmp
    self.pos = _save1
    break
    end # end choice

    break unless _tmp
    end
    _tmp = true
    set_failed_rule :__hyphen_ unless _tmp
    return _tmp
  end

  # eol = "\n"
  def _eol
    _tmp = match_string("\n")
    set_failed_rule :_eol unless _tmp
    return _tmp
  end

  # eof = !.
  def _eof
    _save = self.pos
    _tmp = get_byte
    _tmp = _tmp ? nil : true
    self.pos = _save
    set_failed_rule :_eof unless _tmp
    return _tmp
  end

  # l_bracket = < "{" > { text }
  def _l_bracket

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = match_string("{")
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_l_bracket unless _tmp
    return _tmp
  end

  # r_bracket = < "}" > { text }
  def _r_bracket

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = match_string("}")
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_r_bracket unless _tmp
    return _tmp
  end

  # everything_else = < (!(eol | do_block | bracket_block | "{" | "[") .)* > { text }
  def _everything_else

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    while true

    _save2 = self.pos
    while true # sequence
    _save3 = self.pos

    _save4 = self.pos
    while true # choice
    _tmp = apply(:_eol)
    break if _tmp
    self.pos = _save4
    _tmp = apply(:_do_block)
    break if _tmp
    self.pos = _save4
    _tmp = apply(:_bracket_block)
    break if _tmp
    self.pos = _save4
    _tmp = match_string("{")
    break if _tmp
    self.pos = _save4
    _tmp = match_string("[")
    break if _tmp
    self.pos = _save4
    break
    end # end choice

    _tmp = _tmp ? nil : true
    self.pos = _save3
    unless _tmp
      self.pos = _save2
      break
    end
    _tmp = get_byte
    unless _tmp
      self.pos = _save2
    end
    break
    end # end sequence

    break unless _tmp
    end
    _tmp = true
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_everything_else unless _tmp
    return _tmp
  end

  # single_quote = < "'" single_quote_string "'" > { text }
  def _single_quote

    _save = self.pos
    while true # sequence
    _text_start = self.pos

    _save1 = self.pos
    while true # sequence
    _tmp = match_string("'")
    unless _tmp
      self.pos = _save1
      break
    end
    _tmp = apply(:_single_quote_string)
    unless _tmp
      self.pos = _save1
      break
    end
    _tmp = match_string("'")
    unless _tmp
      self.pos = _save1
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_single_quote unless _tmp
    return _tmp
  end

  # double_quote = < "\"" double_quote_string* "'" > { text }
  def _double_quote

    _save = self.pos
    while true # sequence
    _text_start = self.pos

    _save1 = self.pos
    while true # sequence
    _tmp = match_string("\"")
    unless _tmp
      self.pos = _save1
      break
    end
    while true
    _tmp = apply(:_double_quote_string)
    break unless _tmp
    end
    _tmp = true
    unless _tmp
      self.pos = _save1
      break
    end
    _tmp = match_string("'")
    unless _tmp
      self.pos = _save1
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_double_quote unless _tmp
    return _tmp
  end

  # interop_start = "#{"
  def _interop_start
    _tmp = match_string("\#{")
    set_failed_rule :_interop_start unless _tmp
    return _tmp
  end

  # interop_end = "}"
  def _interop_end
    _tmp = match_string("}")
    set_failed_rule :_interop_end unless _tmp
    return _tmp
  end

  # single_quote_string = /[^']+/
  def _single_quote_string
    _tmp = scan(/\A(?-mix:[^']+)/)
    set_failed_rule :_single_quote_string unless _tmp
    return _tmp
  end

  # double_quote_string = (interop_start interop_body* interop_end | "\\\"" | /[^"]+/)
  def _double_quote_string

    _save = self.pos
    while true # choice

    _save1 = self.pos
    while true # sequence
    _tmp = apply(:_interop_start)
    unless _tmp
      self.pos = _save1
      break
    end
    while true
    _tmp = apply(:_interop_body)
    break unless _tmp
    end
    _tmp = true
    unless _tmp
      self.pos = _save1
      break
    end
    _tmp = apply(:_interop_end)
    unless _tmp
      self.pos = _save1
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save
    _tmp = match_string("\\\"")
    break if _tmp
    self.pos = _save
    _tmp = scan(/\A(?-mix:[^"]+)/)
    break if _tmp
    self.pos = _save
    break
    end # end choice

    set_failed_rule :_double_quote_string unless _tmp
    return _tmp
  end

  # interop_body = (single_quote | double_quote | "\\}" | /[^}]+/)
  def _interop_body

    _save = self.pos
    while true # choice
    _tmp = apply(:_single_quote)
    break if _tmp
    self.pos = _save
    _tmp = apply(:_double_quote)
    break if _tmp
    self.pos = _save
    _tmp = match_string("\\}")
    break if _tmp
    self.pos = _save
    _tmp = scan(/\A(?-mix:[^}]+)/)
    break if _tmp
    self.pos = _save
    break
    end # end choice

    set_failed_rule :_interop_body unless _tmp
    return _tmp
  end

  # indent = < ("module" | "class" | "if" | "until" | "for" | "unless" | "while" | "begin" | "case" | "then" | "rescue" | "def" | "do") > { text }
  def _indent

    _save = self.pos
    while true # sequence
    _text_start = self.pos

    _save1 = self.pos
    while true # choice
    _tmp = match_string("module")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("class")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("if")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("until")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("for")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("unless")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("while")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("begin")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("case")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("then")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("rescue")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("def")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("do")
    break if _tmp
    self.pos = _save1
    break
    end # end choice

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_indent unless _tmp
    return _tmp
  end

  # both = < ("rescue" | "ensure" | "elsif" | "else" | "when") > { text }
  def _both

    _save = self.pos
    while true # sequence
    _text_start = self.pos

    _save1 = self.pos
    while true # choice
    _tmp = match_string("rescue")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("ensure")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("elsif")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("else")
    break if _tmp
    self.pos = _save1
    _tmp = match_string("when")
    break if _tmp
    self.pos = _save1
    break
    end # end choice

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_both unless _tmp
    return _tmp
  end

  # outdent = < "end" > { text }
  def _outdent

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = match_string("end")
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_outdent unless _tmp
    return _tmp
  end

  # do_block = < /do\s*\|[^|]+\|/ > { text }
  def _do_block

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = scan(/\A(?-mix:do\s*\|[^|]+\|)/)
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_do_block unless _tmp
    return _tmp
  end

  # bracket_block = < /\{\s*\|[^|]+\|/ > { text }
  def _bracket_block

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = scan(/\A(?-mix:\{\s*\|[^|]+\|)/)
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_bracket_block unless _tmp
    return _tmp
  end

  # bracket_end = < /[^\[]*\]/ > { text }
  def _bracket_end

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = scan(/\A(?-mix:[^\[]*\])/)
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_bracket_end unless _tmp
    return _tmp
  end

  # brace_end = < /^[^\{]*\}/ > { text }
  def _brace_end

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = scan(/\A(?-mix:^[^\{]*\})/)
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_brace_end unless _tmp
    return _tmp
  end

  # block = (do_block | bracket_block)
  def _block

    _save = self.pos
    while true # choice
    _tmp = apply(:_do_block)
    break if _tmp
    self.pos = _save
    _tmp = apply(:_bracket_block)
    break if _tmp
    self.pos = _save
    break
    end # end choice

    set_failed_rule :_block unless _tmp
    return _tmp
  end

  # str_block_match = < /[A-Z]+/ > &{ @str_token == text }
  def _str_block_match

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = scan(/\A(?-mix:[A-Z]+)/)
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    _save1 = self.pos
    _tmp = begin;  @str_token == text ; end
    self.pos = _save1
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_str_block_match unless _tmp
    return _tmp
  end

  # text_block_start = < /<<-?/ > { text }
  def _text_block_start

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = scan(/\A(?-mix:<<-?)/)
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_text_block_start unless _tmp
    return _tmp
  end

  # pre_text_block = < (!(text_block_start | eol) .)* > { text }
  def _pre_text_block

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    while true

    _save2 = self.pos
    while true # sequence
    _save3 = self.pos

    _save4 = self.pos
    while true # choice
    _tmp = apply(:_text_block_start)
    break if _tmp
    self.pos = _save4
    _tmp = apply(:_eol)
    break if _tmp
    self.pos = _save4
    break
    end # end choice

    _tmp = _tmp ? nil : true
    self.pos = _save3
    unless _tmp
      self.pos = _save2
      break
    end
    _tmp = get_byte
    unless _tmp
      self.pos = _save2
    end
    break
    end # end sequence

    break unless _tmp
    end
    _tmp = true
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_pre_text_block unless _tmp
    return _tmp
  end

  # text_block_label = < /[A-Z]+/ > { @str_token = text; text }
  def _text_block_label

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    _tmp = scan(/\A(?-mix:[A-Z]+)/)
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  @str_token = text; text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_text_block_label unless _tmp
    return _tmp
  end

  # multiline_text = pre_text_block:p text_block_start:s text_block_label:l - eol text_block:b { "#{p}#{s}#{l}\n#{b}" }
  def _multiline_text

    _save = self.pos
    while true # sequence
    _tmp = apply(:_pre_text_block)
    p = @result
    unless _tmp
      self.pos = _save
      break
    end
    _tmp = apply(:_text_block_start)
    s = @result
    unless _tmp
      self.pos = _save
      break
    end
    _tmp = apply(:_text_block_label)
    l = @result
    unless _tmp
      self.pos = _save
      break
    end
    _tmp = apply(:__hyphen_)
    unless _tmp
      self.pos = _save
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save
      break
    end
    _tmp = apply(:_text_block)
    b = @result
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  "#{p}#{s}#{l}\n#{b}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_multiline_text unless _tmp
    return _tmp
  end

  # text_block_lines = < (!str_block_match .)* > { text }
  def _text_block_lines

    _save = self.pos
    while true # sequence
    _text_start = self.pos
    while true

    _save2 = self.pos
    while true # sequence
    _save3 = self.pos
    _tmp = apply(:_str_block_match)
    _tmp = _tmp ? nil : true
    self.pos = _save3
    unless _tmp
      self.pos = _save2
      break
    end
    _tmp = get_byte
    unless _tmp
      self.pos = _save2
    end
    break
    end # end sequence

    break unless _tmp
    end
    _tmp = true
    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  text ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_text_block_lines unless _tmp
    return _tmp
  end

  # text_block = text_block_lines:b str_block_match:m { "#{b}#{@space * @tabs}#{@str_token}" }
  def _text_block

    _save = self.pos
    while true # sequence
    _tmp = apply(:_text_block_lines)
    b = @result
    unless _tmp
      self.pos = _save
      break
    end
    _tmp = apply(:_str_block_match)
    m = @result
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  "#{b}#{@space * @tabs}#{@str_token}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_text_block unless _tmp
    return _tmp
  end

  # line = (< indent (space everything_else)? eol > { code = "#{@space * @tabs}#{text}"; @tabs += 1; code  } | < outdent (space everything_else)? eol > { @tabs -= 1; "#{@space * @tabs}#{text}" } | < both (space everything_else)? eol > { both_tabs = @tabs - 1; "#{@space * both_tabs}#{text}" } | < "[" brace_end eol > { "#{@space * @tabs}#{text}" } | < "[" everything_else eol > { @tabs += 1; "#{@space * (@tabs-1)}#{text}" } | < "]" everything_else eol > { @tabs -= 1; "#{@space * @tabs}#{text}" } | < l_bracket bracket_end eol > { "#{@space * @tabs}#{text}" } | < l_bracket everything_else eol > { @tabs += 1; "#{@space * (@tabs-1)}#{text}" } | < r_bracket everything_else eol > { @tabs -= 1; "#{@space * @tabs}#{text}" } | < everything_else block eol > { @tabs += 1; "#{@space * (@tabs-1)}#{text}" } | multiline_text:e - eol { "#{@space * @tabs}#{e}\n" } | < everything_else eol > { "#{@space * @tabs}#{text}" })
  def _line

    _save = self.pos
    while true # choice

    _save1 = self.pos
    while true # sequence
    _text_start = self.pos

    _save2 = self.pos
    while true # sequence
    _tmp = apply(:_indent)
    unless _tmp
      self.pos = _save2
      break
    end
    _save3 = self.pos

    _save4 = self.pos
    while true # sequence
    _tmp = apply(:_space)
    unless _tmp
      self.pos = _save4
      break
    end
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save4
    end
    break
    end # end sequence

    unless _tmp
      _tmp = true
      self.pos = _save3
    end
    unless _tmp
      self.pos = _save2
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save2
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save1
      break
    end
    @result = begin;  code = "#{@space * @tabs}#{text}"; @tabs += 1; code  ; end
    _tmp = true
    unless _tmp
      self.pos = _save1
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save5 = self.pos
    while true # sequence
    _text_start = self.pos

    _save6 = self.pos
    while true # sequence
    _tmp = apply(:_outdent)
    unless _tmp
      self.pos = _save6
      break
    end
    _save7 = self.pos

    _save8 = self.pos
    while true # sequence
    _tmp = apply(:_space)
    unless _tmp
      self.pos = _save8
      break
    end
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save8
    end
    break
    end # end sequence

    unless _tmp
      _tmp = true
      self.pos = _save7
    end
    unless _tmp
      self.pos = _save6
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save6
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save5
      break
    end
    @result = begin;  @tabs -= 1; "#{@space * @tabs}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save5
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save9 = self.pos
    while true # sequence
    _text_start = self.pos

    _save10 = self.pos
    while true # sequence
    _tmp = apply(:_both)
    unless _tmp
      self.pos = _save10
      break
    end
    _save11 = self.pos

    _save12 = self.pos
    while true # sequence
    _tmp = apply(:_space)
    unless _tmp
      self.pos = _save12
      break
    end
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save12
    end
    break
    end # end sequence

    unless _tmp
      _tmp = true
      self.pos = _save11
    end
    unless _tmp
      self.pos = _save10
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save10
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save9
      break
    end
    @result = begin;  both_tabs = @tabs - 1; "#{@space * both_tabs}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save9
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save13 = self.pos
    while true # sequence
    _text_start = self.pos

    _save14 = self.pos
    while true # sequence
    _tmp = match_string("[")
    unless _tmp
      self.pos = _save14
      break
    end
    _tmp = apply(:_brace_end)
    unless _tmp
      self.pos = _save14
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save14
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save13
      break
    end
    @result = begin;  "#{@space * @tabs}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save13
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save15 = self.pos
    while true # sequence
    _text_start = self.pos

    _save16 = self.pos
    while true # sequence
    _tmp = match_string("[")
    unless _tmp
      self.pos = _save16
      break
    end
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save16
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save16
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save15
      break
    end
    @result = begin;  @tabs += 1; "#{@space * (@tabs-1)}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save15
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save17 = self.pos
    while true # sequence
    _text_start = self.pos

    _save18 = self.pos
    while true # sequence
    _tmp = match_string("]")
    unless _tmp
      self.pos = _save18
      break
    end
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save18
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save18
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save17
      break
    end
    @result = begin;  @tabs -= 1; "#{@space * @tabs}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save17
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save19 = self.pos
    while true # sequence
    _text_start = self.pos

    _save20 = self.pos
    while true # sequence
    _tmp = apply(:_l_bracket)
    unless _tmp
      self.pos = _save20
      break
    end
    _tmp = apply(:_bracket_end)
    unless _tmp
      self.pos = _save20
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save20
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save19
      break
    end
    @result = begin;  "#{@space * @tabs}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save19
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save21 = self.pos
    while true # sequence
    _text_start = self.pos

    _save22 = self.pos
    while true # sequence
    _tmp = apply(:_l_bracket)
    unless _tmp
      self.pos = _save22
      break
    end
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save22
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save22
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save21
      break
    end
    @result = begin;  @tabs += 1; "#{@space * (@tabs-1)}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save21
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save23 = self.pos
    while true # sequence
    _text_start = self.pos

    _save24 = self.pos
    while true # sequence
    _tmp = apply(:_r_bracket)
    unless _tmp
      self.pos = _save24
      break
    end
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save24
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save24
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save23
      break
    end
    @result = begin;  @tabs -= 1; "#{@space * @tabs}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save23
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save25 = self.pos
    while true # sequence
    _text_start = self.pos

    _save26 = self.pos
    while true # sequence
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save26
      break
    end
    _tmp = apply(:_block)
    unless _tmp
      self.pos = _save26
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save26
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save25
      break
    end
    @result = begin;  @tabs += 1; "#{@space * (@tabs-1)}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save25
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save27 = self.pos
    while true # sequence
    _tmp = apply(:_multiline_text)
    e = @result
    unless _tmp
      self.pos = _save27
      break
    end
    _tmp = apply(:__hyphen_)
    unless _tmp
      self.pos = _save27
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save27
      break
    end
    @result = begin;  "#{@space * @tabs}#{e}\n" ; end
    _tmp = true
    unless _tmp
      self.pos = _save27
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save28 = self.pos
    while true # sequence
    _text_start = self.pos

    _save29 = self.pos
    while true # sequence
    _tmp = apply(:_everything_else)
    unless _tmp
      self.pos = _save29
      break
    end
    _tmp = apply(:_eol)
    unless _tmp
      self.pos = _save29
    end
    break
    end # end sequence

    if _tmp
      text = get_text(_text_start)
    end
    unless _tmp
      self.pos = _save28
      break
    end
    @result = begin;  "#{@space * @tabs}#{text}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save28
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save
    break
    end # end choice

    set_failed_rule :_line unless _tmp
    return _tmp
  end

  # code = (- line:l code:c { "#{l}#{c}" } | - line:l { "#{l}" })
  def _code

    _save = self.pos
    while true # choice

    _save1 = self.pos
    while true # sequence
    _tmp = apply(:__hyphen_)
    unless _tmp
      self.pos = _save1
      break
    end
    _tmp = apply(:_line)
    l = @result
    unless _tmp
      self.pos = _save1
      break
    end
    _tmp = apply(:_code)
    c = @result
    unless _tmp
      self.pos = _save1
      break
    end
    @result = begin;  "#{l}#{c}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save1
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save

    _save2 = self.pos
    while true # sequence
    _tmp = apply(:__hyphen_)
    unless _tmp
      self.pos = _save2
      break
    end
    _tmp = apply(:_line)
    l = @result
    unless _tmp
      self.pos = _save2
      break
    end
    @result = begin;  "#{l}" ; end
    _tmp = true
    unless _tmp
      self.pos = _save2
    end
    break
    end # end sequence

    break if _tmp
    self.pos = _save
    break
    end # end choice

    set_failed_rule :_code unless _tmp
    return _tmp
  end

  # root = code:c eof { @processed = c }
  def _root

    _save = self.pos
    while true # sequence
    _tmp = apply(:_code)
    c = @result
    unless _tmp
      self.pos = _save
      break
    end
    _tmp = apply(:_eof)
    unless _tmp
      self.pos = _save
      break
    end
    @result = begin;  @processed = c ; end
    _tmp = true
    unless _tmp
      self.pos = _save
    end
    break
    end # end sequence

    set_failed_rule :_root unless _tmp
    return _tmp
  end

  Rules = {}
  Rules[:_space] = rule_info("space", "\" \"")
  Rules[:_tab] = rule_info("tab", "\"\\t\"")
  Rules[:__hyphen_] = rule_info("-", "(space | tab)*")
  Rules[:_eol] = rule_info("eol", "\"\\n\"")
  Rules[:_eof] = rule_info("eof", "!.")
  Rules[:_l_bracket] = rule_info("l_bracket", "< \"{\" > { text }")
  Rules[:_r_bracket] = rule_info("r_bracket", "< \"}\" > { text }")
  Rules[:_everything_else] = rule_info("everything_else", "< (!(eol | do_block | bracket_block | \"{\" | \"[\") .)* > { text }")
  Rules[:_single_quote] = rule_info("single_quote", "< \"'\" single_quote_string \"'\" > { text }")
  Rules[:_double_quote] = rule_info("double_quote", "< \"\\\"\" double_quote_string* \"'\" > { text }")
  Rules[:_interop_start] = rule_info("interop_start", "\"\#{\"")
  Rules[:_interop_end] = rule_info("interop_end", "\"}\"")
  Rules[:_single_quote_string] = rule_info("single_quote_string", "/[^']+/")
  Rules[:_double_quote_string] = rule_info("double_quote_string", "(interop_start interop_body* interop_end | \"\\\\\\\"\" | /[^\"]+/)")
  Rules[:_interop_body] = rule_info("interop_body", "(single_quote | double_quote | \"\\\\}\" | /[^}]+/)")
  Rules[:_indent] = rule_info("indent", "< (\"module\" | \"class\" | \"if\" | \"until\" | \"for\" | \"unless\" | \"while\" | \"begin\" | \"case\" | \"then\" | \"rescue\" | \"def\" | \"do\") > { text }")
  Rules[:_both] = rule_info("both", "< (\"rescue\" | \"ensure\" | \"elsif\" | \"else\" | \"when\") > { text }")
  Rules[:_outdent] = rule_info("outdent", "< \"end\" > { text }")
  Rules[:_do_block] = rule_info("do_block", "< /do\\s*\\|[^|]+\\|/ > { text }")
  Rules[:_bracket_block] = rule_info("bracket_block", "< /\\{\\s*\\|[^|]+\\|/ > { text }")
  Rules[:_bracket_end] = rule_info("bracket_end", "< /[^\\[]*\\]/ > { text }")
  Rules[:_brace_end] = rule_info("brace_end", "< /^[^\\{]*\\}/ > { text }")
  Rules[:_block] = rule_info("block", "(do_block | bracket_block)")
  Rules[:_str_block_match] = rule_info("str_block_match", "< /[A-Z]+/ > &{ @str_token == text }")
  Rules[:_text_block_start] = rule_info("text_block_start", "< /<<-?/ > { text }")
  Rules[:_pre_text_block] = rule_info("pre_text_block", "< (!(text_block_start | eol) .)* > { text }")
  Rules[:_text_block_label] = rule_info("text_block_label", "< /[A-Z]+/ > { @str_token = text; text }")
  Rules[:_multiline_text] = rule_info("multiline_text", "pre_text_block:p text_block_start:s text_block_label:l - eol text_block:b { \"\#{p}\#{s}\#{l}\\n\#{b}\" }")
  Rules[:_text_block_lines] = rule_info("text_block_lines", "< (!str_block_match .)* > { text }")
  Rules[:_text_block] = rule_info("text_block", "text_block_lines:b str_block_match:m { \"\#{b}\#{@space * @tabs}\#{@str_token}\" }")
  Rules[:_line] = rule_info("line", "(< indent (space everything_else)? eol > { code = \"\#{@space * @tabs}\#{text}\"; @tabs += 1; code  } | < outdent (space everything_else)? eol > { @tabs -= 1; \"\#{@space * @tabs}\#{text}\" } | < both (space everything_else)? eol > { both_tabs = @tabs - 1; \"\#{@space * both_tabs}\#{text}\" } | < \"[\" brace_end eol > { \"\#{@space * @tabs}\#{text}\" } | < \"[\" everything_else eol > { @tabs += 1; \"\#{@space * (@tabs-1)}\#{text}\" } | < \"]\" everything_else eol > { @tabs -= 1; \"\#{@space * @tabs}\#{text}\" } | < l_bracket bracket_end eol > { \"\#{@space * @tabs}\#{text}\" } | < l_bracket everything_else eol > { @tabs += 1; \"\#{@space * (@tabs-1)}\#{text}\" } | < r_bracket everything_else eol > { @tabs -= 1; \"\#{@space * @tabs}\#{text}\" } | < everything_else block eol > { @tabs += 1; \"\#{@space * (@tabs-1)}\#{text}\" } | multiline_text:e - eol { \"\#{@space * @tabs}\#{e}\\n\" } | < everything_else eol > { \"\#{@space * @tabs}\#{text}\" })")
  Rules[:_code] = rule_info("code", "(- line:l code:c { \"\#{l}\#{c}\" } | - line:l { \"\#{l}\" })")
  Rules[:_root] = rule_info("root", "code:c eof { @processed = c }")
end
