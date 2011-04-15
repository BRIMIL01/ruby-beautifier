require 'test/unit'
require 'ruby-beautifier/beautifier'

class TestBeautifier < Test::Unit::TestCase
  def test_parse_simple_block
    output = <<-STR
class Test
  if something > 0
    blah
  else
    blah
  end
end
    STR
    input = <<-STR
class Test
  if something > 0
    blah
  else
    blah
  end
end
    STR
    parser = RubyBeautifier.new(input)
    assert_equal true, parser.parse
  end

  def test_simple_block
    output = <<-STR
class Test
  if something > 0
    blah
  else
    blah
  end
end
    STR
    input = <<-STR
class Test
if something > 0
blah
else
blah
end
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

  def test_while_loop
    input = <<-STR
if something
while true # choice
_tmp = apply(:_dbl_string)
break if _tmp
self.pos = _save
_tmp = apply(:_sgl_string)
break if _tmp
self.pos = _save
break
end # end choice
end
    STR

    output = <<-STR
if something
  while true # choice
    _tmp = apply(:_dbl_string)
    break if _tmp
    self.pos = _save
    _tmp = apply(:_sgl_string)
    break if _tmp
    self.pos = _save
    break
  end # end choice
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

  def test_do_block
    input = <<-STR
class Test
if something > 0
5.times do |i|
blah
end
else
blah
end
end
    STR
    output = <<-STR
class Test
  if something > 0
    5.times do |i|
      blah
    end
  else
    blah
  end
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

  def test_brace_block
    input = <<-STR
class Test
if something > 0
5.times do {|i|
blah
}
else
blah
end
end
    STR
    output = <<-STR
class Test
  if something > 0
    5.times do {|i|
      blah
    }
  else
    blah
  end
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

  def test_quotes_are_left_alone
    output = <<-STR
class Test
  if something > 0
    "something about something"
  else
    blah
  end
end
    STR
    input = <<-STR
class Test
if something > 0
"something about something"
else
blah
end
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

  def test_quotes_with_interop_are_left_alone
    output = <<-STR
class Test
  if something > 0
    "something #{@test if @test} something"
  else
    blah
  end
end
    STR
    input = <<-STR
class Test
if something > 0
"something #{@test if @test} something"
else
blah
end
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

  def test_should_not_match_variables_that_start_with_keywords
    output = <<-STR
class Test
  if something > 0
    done = false
  else
    ifirit = "fire!"
  end
end
    STR
    input = <<-STR
class Test
if something > 0
done = false
else
ifirit = "fire!"
end
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

  def test_string_blocks
    output = <<-STR
class Test
  p <<END
test of the
  string blocks
so this should not
be
      formatted
  END
end
    STR
    input = <<-STR
class Test
p <<END
test of the
  string blocks
so this should not
be
      formatted
END
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

    def test_multiple_string_blocks
    output = <<-STR
class Test
  p <<END
test of the
  string blocks
so this should not
be
      formatted
  END
  if test
    something
  else
    p = <<ELSE
this
should
  not
      be
      formatted

    ELSE
  end
end
    STR
    input = <<-STR
class Test
p <<END
test of the
  string blocks
so this should not
be
      formatted
END
if test
something
else
p = <<ELSE
this
should
  not
      be
      formatted

ELSE
end
end
    STR
    parser = RubyBeautifier.new(input)
    parser.parse
    assert_equal output, parser.processed
  end

end

