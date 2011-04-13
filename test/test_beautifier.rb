require 'test/unit'
require 'kpeg/beautifier.kpeg'

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
    parser = Beautifier.new(input)
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
    parser = Beautifier.new(input)
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
    parser = Beautifier.new(input)
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
    parser = Beautifier.new(input)
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
      parser = Beautifier.new(input)
      parser.parse
      assert_equal output, parser.processed
    end
end