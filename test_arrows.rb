# frozen_string_literal: true
#
# test_arrows.rb — paste into SketchUp Ruby Console (Window > Ruby Console)
#
# What it does:
#   1. Prints every Layout::Style constant whose name contains "ARROW"
#   2. Opens (or reuses) the active Layout document
#   3. Places one label per arrow type on the first page so you can see them all
#   4. Also tests three arrow sizes for the first valid type
#
# Run:  load 'C:/Users/yhammadi/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/YH_SmartLeaders/test_arrows.rb'

puts "\n=== Layout Arrow Type Constants ==="

arrow_constants = Layout::Style.constants.select { |c| c.to_s.include?('ARROW') }

if arrow_constants.empty?
  puts "No ARROW constants found on Layout::Style — trying Layout::Label..."
  arrow_constants = Layout::Label.constants.select { |c| c.to_s.include?('ARROW') }
  arrow_source = Layout::Label
else
  arrow_source = Layout::Style
end

if arrow_constants.empty?
  puts "No ARROW constants found on Layout::Label either."
  puts "Trying brute-force integer scan on Layout::Style arrow setters..."
  arrow_constants = []
  arrow_source    = nil
end

arrow_constants.each do |c|
  val = arrow_source.const_get(c)
  puts "  #{arrow_source}::#{c} = #{val.inspect}"
end

# ── Open or get the active Layout document ──────────────────────────────────
doc = Layout::Document.open(
  UI.openpanel('Choose a Layout file to test arrows on', '', 'Layout Files|*.layout||')
)

unless doc
  puts "No document opened — aborting."
  return
end

page  = doc.pages.first
layer = doc.layers.first

puts "\n=== Placing test labels ==="

y = 1.0   # starting Y on paper (inches from top)

if arrow_constants.any?
  arrow_constants.each_with_index do |const_name, i|
    arrow_val = arrow_source.const_get(const_name)

    target_pt   = Geom::Point2d.new(3.0, y)
    text_bounds = Geom::Bounds2d.new(3.5, y - 0.10, 2.5, 0.20)

    begin
      label = Layout::Label.new(
        const_name.to_s,
        Layout::Label::LEADER_LINE_TYPE_SINGLE_SEGMENT,
        target_pt,
        text_bounds
      )

      # Try setting arrow on the label's style
      begin
        s = label.style
        s.end_arrow_type = arrow_val   # arrow is at the target/arrow end
        label.style = s
        puts "  [OK style.end_arrow_type] #{const_name}"
      rescue => e1
        puts "  [FAIL style.end_arrow_type] #{const_name}: #{e1.message}"
        # Try start_arrow_type
        begin
          s = label.style
          s.start_arrow_type = arrow_val
          label.style = s
          puts "  [OK style.start_arrow_type] #{const_name}"
        rescue => e2
          puts "  [FAIL style.start_arrow_type] #{const_name}: #{e2.message}"
        end
      end

      doc.add_entity(label, layer, page)
    rescue => e
      puts "  [FAIL label creation] #{const_name}: #{e.message}"
    end

    y += 0.40
  end
else
  # Brute-force: try integer values 0..20 for arrow type
  puts "Brute-forcing arrow type integers 0..20 on Layout::Style..."
  (0..20).each do |i|
    target_pt   = Geom::Point2d.new(3.0, y)
    text_bounds = Geom::Bounds2d.new(3.5, y - 0.10, 2.0, 0.20)

    begin
      label = Layout::Label.new(
        "arrow_type_#{i}",
        Layout::Label::LEADER_LINE_TYPE_SINGLE_SEGMENT,
        target_pt,
        text_bounds
      )
      s = label.style
      s.end_arrow_type = i
      label.style = s
      doc.add_entity(label, layer, page)
      puts "  [OK] integer arrow type #{i}"
    rescue => e
      puts "  [FAIL] integer #{i}: #{e.message}"
    end

    y += 0.40
  end
end

# ── Test arrow sizes on whatever type worked ─────────────────────────────────
puts "\n=== Testing arrow sizes ==="
y += 0.20
[0.05, 0.10, 0.20, 0.30].each do |sz|
  target_pt   = Geom::Point2d.new(3.0, y)
  text_bounds = Geom::Bounds2d.new(3.5, y - 0.10, 2.0, 0.20)

  begin
    label = Layout::Label.new(
      "size_#{sz}",
      Layout::Label::LEADER_LINE_TYPE_SINGLE_SEGMENT,
      target_pt,
      text_bounds
    )
    s = label.style
    # Try to set the first valid arrow type and size
    begin
      s.end_arrow_type = arrow_constants.any? ? arrow_source.const_get(arrow_constants.first) : 1
      s.end_arrow_size = sz
      label.style = s
      puts "  [OK] size #{sz}"
    rescue => e
      puts "  [FAIL] size #{sz}: #{e.message}"
    end
    doc.add_entity(label, layer, page)
  rescue => e
    puts "  [FAIL label] size #{sz}: #{e.message}"
  end

  y += 0.40
end

# Save alongside original so the test file is easy to find
test_path = doc.path.sub(/\.layout$/i, '_arrow_test.layout')
doc.save(test_path)
puts "\nSaved test document: #{test_path}"
puts "Open it in Layout to inspect the results visually."
