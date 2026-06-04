# frozen_string_literal: true

module YH
module SmartLeaders

DEFAULT_SETTINGS = {
  arrow_size: 0.6,
  leader_offset: 2.0,
  rp_extra_offset: 1.0,
  text_offset: 0.25
}.freeze

def self.settings
  model = Sketchup.active_model

  {
    arrow_size: model.get_attribute(
      DICT,
      'arrow_size',
      DEFAULT_SETTINGS[:arrow_size]
    ),

    leader_offset: model.get_attribute(
      DICT,
      'leader_offset',
      DEFAULT_SETTINGS[:leader_offset]
    ),

    rp_extra_offset: model.get_attribute(
      DICT,
      'rp_extra_offset',
      DEFAULT_SETTINGS[:rp_extra_offset]
    ),

    text_offset: model.get_attribute(
  DICT,
  'text_offset',
  DEFAULT_SETTINGS[:text_offset]
)
  }
end

def self.show_settings

  model = Sketchup.active_model

  s = settings

  offset = s[:leader_offset].inch
  
  text_gap = s[:text_offset].inch

  prompts = [
    'Arrow Size (inches)',
    'Leader Offset (inches)',
    'RP Extra Offset (inches)',
    'Text Offset (inches)'
  ]

  defaults = [
    s[:arrow_size],
    s[:leader_offset],
    s[:rp_extra_offset],
    s[:text_offset]
  ]

  values = UI.inputbox(
    prompts,
    defaults,
    'Smart Leaders Settings'
  )

  return unless values

  model.set_attribute(
    DICT,
    'arrow_size',
    values[0].to_f
  )

  model.set_attribute(
    DICT,
    'leader_offset',
    values[1].to_f
  )

  model.set_attribute(
    DICT,
    'rp_extra_offset',
    values[2].to_f
  )

  model.set_attribute(
  DICT,
  'text_offset',
  values[3].to_f
)

  UI.messagebox('Settings saved.')

end

DICT = 'YH_SMART_LEADERS'.freeze

def self.draw_arrow(ents, tip, tail, axis = Z_AXIS, size = 0.60.inch)

  vec = tail.vector_to(tip)
  vec.length = size

  left  = vec.clone
  right = vec.clone

  left.transform!(Geom::Transformation.rotation(
    tip, axis, 150.degrees
  ))

  right.transform!(Geom::Transformation.rotation(
    tip, axis, -150.degrees
  ))

  p1 = tip.offset(left)
  p2 = tip.offset(right)

  face = ents.add_face(tip, p1, p2)

if face

  black = Sketchup::Color.new(0, 0, 0)

  face.material = black
  face.back_material = black

end

end


def self.generate

  model = Sketchup.active_model
  sel   = model.selection

  groups = sel.grep(Sketchup::Group)

  if groups.empty?
    UI.messagebox('Select one or more cabinet groups.')
    return
  end

  scene_name =
    model.pages.selected_page ?
      model.pages.selected_page.name.upcase :
      ''

  model.start_operation('Generate Leaders', true)

  groups.each do |cabinet|

    leader_group_name = "YH_LEADERS_#{scene_name}"

old = cabinet.entities.grep(Sketchup::Group).find { |g|
  g.name == leader_group_name
}

    old.erase! if old&.valid?

    leader_group_name = "YH_LEADERS_#{scene_name}"

leaders_group = cabinet.entities.add_group
leaders_group.name = leader_group_name
if scene_name.include?('ELEV_NO_DOORS')
  leader_tag_name = 'TAG_ASM_ELEV_NO_DOORS'

elsif scene_name.include?('ELEV')
  leader_tag_name = 'TAG_ASM_ELEV'

else
  leader_tag_name = 'TAG_ASM_PLAN'
end

leader_tag = model.layers[leader_tag_name]

unless leader_tag
  leader_tag = model.layers.add(leader_tag_name)
end

leaders_group.layer = leader_tag
    ents = leaders_group.entities

    cabinet_parts =
      cabinet.entities.grep(Sketchup::ComponentInstance)
puts "PART COUNT = #{cabinet_parts.size}"
cabinet_parts.each { |p| puts p.definition.name }



    cabinet_parts.each do |part|

  part_name = part.definition.name.to_s.upcase

  next unless show_part?(part_name, scene_name)

  bb = part.bounds


 s = settings

offset = s[:leader_offset].inch

text_gap = s[:text_offset].inch

if scene_name.include?('PLAN')

  case part_name

  when /_LP$/

    center = Geom::Point3d.new(
      bb.max.x,
      (bb.min.y + bb.max.y) / 2,
      bb.max.z
    )

    line_pt = center.offset(X_AXIS, offset)

    text_pt = line_pt.offset(X_AXIS, text_gap)

  when /_RP$/

  center = Geom::Point3d.new(
    bb.min.x,
    (bb.min.y + bb.max.y) / 2,
    bb.max.z
  )

  line_pt = center.offset(X_AXIS.reverse, offset)

  text_pt = line_pt.offset(X_AXIS.reverse, text_gap)
  

  when /_BK$/

    center = Geom::Point3d.new(
      (bb.min.x + bb.max.x) / 2,
      bb.min.y,
      bb.max.z
    )

    line_pt = center.offset(Y_AXIS.reverse, offset)

    text_pt = line_pt.offset(Y_AXIS.reverse, text_gap)

  when /_B$/

    center = Geom::Point3d.new(
      (bb.min.x + bb.max.x) / 2,
      (bb.min.y + bb.max.y) / 2,
      bb.max.z
    )

    line_pt = center.offset(Y_AXIS.reverse, offset)

    text_pt = line_pt.offset(Y_AXIS.reverse, text_gap)

  when /_TP$/

    center = Geom::Point3d.new(
      (bb.min.x + bb.max.x) / 2,
      (bb.min.y + bb.max.y) / 2,
      bb.max.z
    )

    line_pt = center.offset(Y_AXIS, offset)

    text_pt = line_pt.offset(Y_AXIS, text_gap)

  when /_ST/

    cab_center_y = cabinet.bounds.center.y

    if bb.center.y > cab_center_y
      # FRONT ST

      center = Geom::Point3d.new(
        (bb.min.x + bb.max.x) / 2,
        bb.min.y,
        bb.max.z
      )

      line_pt = center.offset(Y_AXIS.reverse, offset)

      text_pt = line_pt.offset(Y_AXIS.reverse, text_gap)

    else
      # REAR ST

      center = Geom::Point3d.new(
        (bb.min.x + bb.max.x) / 2,
        bb.max.y,
        bb.max.z
      )

      line_pt = center.offset(Y_AXIS, offset)

      text_pt = line_pt.offset(Y_AXIS, text_gap)

    end

     when /_DR/

    center = Geom::Point3d.new(
      (bb.min.x + bb.max.x) / 2,
      bb.min.y,
      bb.max.z
    )

    line_pt = center.offset(Y_AXIS.reverse, offset)

    text_pt = line_pt.offset(Y_AXIS.reverse, text_gap)

     when /_DW/

    center = Geom::Point3d.new(
      (bb.min.x + bb.max.x) / 2,
      bb.min.y,
      bb.max.z
    )

    line_pt = center.offset(Y_AXIS.reverse, offset)

    text_pt = line_pt.offset(Y_AXIS.reverse, text_gap)

    when /_SH/

    center = Geom::Point3d.new(
      (bb.min.x + bb.max.x) / 2,
      (bb.min.y + bb.max.y) / 2,
      bb.max.z
    )

    line_pt = center.offset(Y_AXIS.reverse, offset)

    text_pt = line_pt.offset(Y_AXIS.reverse, text_gap)

    else

    center = bb.center
    text_pt = center.offset(X_AXIS, offset)

  end

elsif scene_name.include?('ELEV')

  has_fronts = !scene_name.include?('NO_DOORS')

  puts "ELEV PART = #{part_name}"
  puts "HAS_FRONTS = #{has_fronts}"

  if has_fronts

    next unless part_name.include?('_DR') ||
                part_name.include?('_DW')

  else

  next if part_name.include?('_DR')
  next if part_name.include?('_DW')

end

  case part_name

when /_DR/

  center = Geom::Point3d.new(
    bb.min.x  + 2,
    bb.min.y,
    (bb.min.z + bb.max.z) / 2
  )

  line_pt = center.offset(X_AXIS, offset)

  text_pt = line_pt.offset(X_AXIS, text_gap)

when /_DW/

  center = Geom::Point3d.new(
    bb.min.x + 2,
    bb.min.y,
    (bb.min.z + bb.max.z) / 2
  )

  line_pt = center.offset(X_AXIS, offset)

  text_pt = line_pt.offset(X_AXIS, text_gap)

when /_LP$/

  center = Geom::Point3d.new(
    bb.max.x,
    bb.min.y,
    bb.max.z - 2
  )

  line_pt = center.offset(X_AXIS, offset)

  text_pt = line_pt.offset(X_AXIS, text_gap)

when /_RP$/

  center = Geom::Point3d.new(
    bb.min.x,
    bb.min.y,
    bb.max.z - 2
  )

  line_pt = center.offset(X_AXIS.reverse, offset)

  text_pt = line_pt.offset(X_AXIS.reverse, text_gap)

when /_BK$/

  center = Geom::Point3d.new(
    (bb.min.x + bb.max.x) / 2,
    bb.min.y,
    bb.min.z + 6
  )

  line_pt = center.offset(Z_AXIS, offset)

  text_pt = line_pt.offset(Z_AXIS, text_gap)

when /_TP$/

  center = Geom::Point3d.new(
    (bb.min.x + bb.max.x) / 2,
    bb.min.y,
    bb.min.z
  )

  line_pt = center.offset(Z_AXIS.reverse, offset)

  text_pt = line_pt.offset(Z_AXIS.reverse, text_gap)

when /_B$/

  center = Geom::Point3d.new(
    (bb.min.x + bb.max.x) / 2,
    bb.min.y,
    bb.max.z
  )

  line_pt = center.offset(Z_AXIS, offset)

  text_pt = line_pt.offset(Z_AXIS, text_gap)

when /_ST/

  center = Geom::Point3d.new(
    (bb.min.x + bb.max.x) / 2,
    bb.min.y,
    bb.min.z
  )

  line_pt = center.offset(Z_AXIS.reverse, offset)

  text_pt = line_pt.offset(Z_AXIS.reverse, text_gap)

when /_SH/

  center = Geom::Point3d.new(
    (bb.min.x + bb.max.x) / 2,
    bb.min.y,
    bb.max.z
  )

  line_pt = center.offset(Z_AXIS, offset)

  text_pt = line_pt.offset(Z_AXIS, text_gap)

else

  next

end

  
  end   # <-- closes PLAN/ELEV if

next unless center
  next unless text_pt

  leader_pt = defined?(line_pt) && line_pt ? line_pt : text_pt

ents.add_line(center, leader_pt)

if scene_name.include?('ELEV')

  draw_arrow(
    ents,
    center,
    leader_pt,
    Y_AXIS,
    s[:arrow_size].inch
  )

else

  draw_arrow(
    ents,
    center,
    leader_pt,
    Z_AXIS,
    s[:arrow_size].inch

  )

end

line_pt = nil

  # Text
  ents.add_text(
    part_name,
    text_pt
  )

end

  end

  model.commit_operation

end

def self.show_part?(name, scene)

  if scene.include?('PLAN')

    return true if name.include?('_LP')
    return true if name.include?('_RP')
    return true if name.include?('_TP')
    return true if name.include?('_B')
    return true if name.include?('_BK')
    return true if name.include?('_SH')
    return true if name.include?('_ST')
    return true if name.include?('_VS')
    return true if name.include?('_DR')
    return true if name.include?('_DW')

    return false

  end

  if scene.include?('ELEV')

  return true if name.include?('_LP')
  return true if name.include?('_RP')
  return true if name.include?('_BK')
  return true if name.include?('_B')
  return true if name.include?('_TP')
  return true if name.include?('_ST')
  return true if name.include?('_SH')
  return true if name.include?('_VS')
  return true if name.include?('_DR')
  return true if name.include?('_DW')

  return false

end

  if scene.include?('SECTION')

    return true

  end

  true

end

def self.update_all_leaders

  model = Sketchup.active_model

  model.start_operation('Update All Leaders', true)

  cabinets = []

  model.entities.grep(Sketchup::Group).each do |g|

    has_leaders = g.entities.grep(Sketchup::Group).any? { |x|
      x.name.start_with?('YH_LEADERS_')
    }

    cabinets << g if has_leaders

  end

  model.selection.clear
  cabinets.each { |c| model.selection.add(c) }

  generate

  model.commit_operation

end

unless file_loaded?(__FILE__)

  toolbar = UI::Toolbar.new('YH Smart Leaders')

cmd_generate = UI::Command.new('Generate Leaders') {
  self.generate
}

cmd_generate.tooltip = 'Generate Leaders'

cmd_update = UI::Command.new('Update All Leaders') {
  self.update_all_leaders
}

cmd_update.tooltip = 'Update All Leaders'

cmd_settings = UI::Command.new('Smart Leaders Settings') {
  self.show_settings
}

cmd_settings.tooltip = 'Smart Leaders Settings'

# Icons
cmd_generate.small_icon = File.join(__dir__, 'icons', 'generate.svg')
cmd_generate.large_icon = File.join(__dir__, 'icons', 'generate.svg')

cmd_update.small_icon = File.join(__dir__, 'icons', 'update.svg')
cmd_update.large_icon = File.join(__dir__, 'icons', 'update.svg')

cmd_settings.small_icon = File.join(__dir__, 'icons', 'settings.svg')
cmd_settings.large_icon = File.join(__dir__, 'icons', 'settings.svg')

cmd_assembly = UI::Command.new('Generate Assembly Scenes') {
  self.generate_assembly_scenes
}

cmd_assembly.tooltip = 'Generate Assembly Scenes'

cmd_assembly_leaders = UI::Command.new(
  'Generate Assembly Leaders'
) {
  self.generate_assembly_leaders
}

cmd_assembly_leaders.tooltip =
  'Generate Assembly Leaders'

toolbar.add_item(cmd_generate)
toolbar.add_item(cmd_update)
toolbar.add_item(cmd_settings)
toolbar.add_item(cmd_assembly)
toolbar.add_item(cmd_assembly_leaders)

toolbar.restore

  menu = UI.menu('Extensions')
  menu.add_item('Generate Leaders') {
    self.generate
  }

  menu.add_item('Update All Leaders') {
  self.update_all_leaders
}

  menu.add_item('Smart Leaders Settings') {
  self.show_settings
}

  menu.add_item('Generate Assembly Scenes') {
  self.generate_assembly_scenes
}

  menu.add_item('Generate Assembly Leaders') {
  self.generate_assembly_leaders
}

  menu.add_item('Layout Test') {
  self.layout_test
}

  menu.add_item('Generate Assembly Package') {
  self.generate_assembly_package
}

def self.generate_assembly_scenes

  model = Sketchup.active_model

  sel = model.selection.to_a

  puts "SELECTED CABINETS = #{sel.size}"
sel.each { |c| puts c.name }

  if sel.empty?
    UI.messagebox("Select one or more cabinets first.")
    return
  end

  model.start_operation(
    "Generate Assembly Scenes",
    true
  )

  tag_plan = model.layers["TAG_ASM_PLAN"] ||
           model.layers.add("TAG_ASM_PLAN")

  tag_elev = model.layers["TAG_ASM_ELEV"] ||
           model.layers.add("TAG_ASM_ELEV")

  tag_no_doors = model.layers["TAG_ASM_ELEV_NO_DOORS"] ||
               model.layers.add("TAG_ASM_ELEV_NO_DOORS")

  sel.each do |cabinet|

  next unless cabinet.is_a?(Sketchup::Group)

  cab_name = cabinet.name

  

  puts "CABINET: #{cab_name}"

  # Hide all selected cabinets
  sel.each do |c|
    next unless c.is_a?(Sketchup::Group)
    c.hidden = true
  end

  # Show current cabinet
  cabinet.hidden = false

view = model.active_view
cam  = view.camera

# PLAN VIEW (TOP)
cam.perspective = false

cam.set(
  cabinet.bounds.center.offset(Z_AXIS, 1000),
  cabinet.bounds.center,
  Y_AXIS
)

view.zoom(cabinet)

plan_scene = "ASM_#{cab_name}_PLAN"

  tag_plan.visible = true
  tag_elev.visible = false
  tag_no_doors.visible = false

existing = model.pages[plan_scene]

if existing
  model.pages.erase(existing)
end

model.pages.add(plan_scene)


puts "CREATED: #{plan_scene}"


# ELEVATION VIEW (FRONT)
cam.set(
  cabinet.bounds.center.offset(Y_AXIS.reverse, 1000),
  cabinet.bounds.center,
  Z_AXIS
)

view.zoom(cabinet)

elev_scene = "ASM_#{cab_name}_ELEV"

  tag_plan.visible = false
  tag_elev.visible = true
  tag_no_doors.visible = false

existing = model.pages[elev_scene]

if existing
  model.pages.erase(existing)
end

model.pages.add(elev_scene)


puts "CREATED: #{elev_scene}"

doors_tag = model.layers["TAG_DOORS"]

if doors_tag
  doors_tag.visible = false
end

drawer_tag = model.layers["TAG_DRAWERS"]

drawer_tag.visible = false if drawer_tag


elev_no_doors_scene = "ASM_#{cab_name}_ELEV_NO_DOORS"

  tag_plan.visible = false
  tag_elev.visible = false
  tag_no_doors.visible = true

existing = model.pages[elev_no_doors_scene]

if existing
  model.pages.erase(existing)
end

model.pages.add(elev_no_doors_scene)


puts "CREATED: #{elev_no_doors_scene}"

doors_tag.visible = true if doors_tag
drawer_tag.visible = true if drawer_tag

puts "CABINET FINISHED: #{cab_name}"


end

# Restore visibility
sel.each do |c|
  next unless c.is_a?(Sketchup::Group)
  c.hidden = false
end

  model.commit_operation

end

def self.generate_assembly_leaders

  model = Sketchup.active_model

  asm_pages = []

  model.pages.each do |page|

    if page.name.start_with?('ASM_')
      asm_pages << page
    end

  end

  puts "ASSEMBLY SCENES = #{asm_pages.size}"

  asm_pages.each do |page|

    puts "SCENE: #{page.name}"

    parts = page.name.split('_')

    cab_name = parts[1]

    cabinet = model.entities.grep(Sketchup::Group).find { |g|
      g.name == cab_name
    }

    next unless cabinet

    model.pages.selected_page = page

    model.selection.clear
    model.selection.add(cabinet)

    self.generate


  end

end


  def self.generate_assembly_package

  model = Sketchup.active_model

  if model.path.empty?
    UI.messagebox("Save the SketchUp model first.")
    return
  end

  template = UI.openpanel(
  "Select Layout Template",
  "",
  "*.layout"
)

return unless template

prompts = [
  "Plan Scale (1:X)",
  "Elevation Scale (1:X)",
  "No Doors Scale (1:X)"
]

defaults = [
  "16",
  "16",
  "16"
]

results = UI.inputbox(
  prompts,
  defaults,
  "Assembly Package Settings"
)

return unless results

plan_scale_denom,
elev_scale_denom,
no_doors_scale_denom = results.map(&:to_f)

plan_scale     = 1.0 / plan_scale_denom
elev_scale     = 1.0 / elev_scale_denom
no_doors_scale = 1.0 / no_doors_scale_denom

begin

  doc = Layout::Document.open(template)

    page = doc.pages.first

    scenes = model.pages.map(&:name).grep(/^ASM_/)

    puts "ASM SCENES FOUND = #{scenes.size}"

    cabinets = scenes.map { |name|

  name[/ASM_(.+?)_/, 1]

}.uniq.sort

puts "CABINETS FOUND:"
puts cabinets.inspect

template_page = page

cabinets.each_slice(3).with_index do |cab_group, page_index|

  if page_index == 0

  else

    page = doc.pages.add(
  "ASM_#{cab_group.first}_TO_#{cab_group.last}"
)

  end

  puts ""
  puts "PAGE #{page_index + 1}"
  puts cab_group.inspect

  cab_group.each_with_index do |cab, col|

    x = 1.0 + (col * 5.0)

title = Layout::FormattedText.new(
  "CABINET #{cab}",
  Geom::Bounds2d.new(
    Geom::Point2d.new(x, 10),
    Geom::Point2d.new(x + 3.0, 10.25)
  )
)

doc.add_entity(
  title,
  doc.layers[3],
  page
)

    views = [

      ["ASM_#{cab}_PLAN",          x, 7.25],
      ["ASM_#{cab}_ELEV",          x, 4.125],
      ["ASM_#{cab}_ELEV_NO_DOORS", x, 1.0]

    ]

    views.each do |scene_name, vx, vy|

view_label =
  if scene_name.end_with?("_PLAN")
    "PLAN"
  elsif scene_name.end_with?("_ELEV_NO_DOORS")
    "ELEVATION - NO DOORS"
  elsif scene_name.end_with?("_ELEV")
    "ELEVATION"
  else
    ""
  end

label = Layout::FormattedText.new(
  view_label,
  Geom::Bounds2d.new(
    Geom::Point2d.new(vx, vy + 2.55),
    Geom::Point2d.new(vx + 4.0, vy + 2.80)
  )
)

doc.add_entity(
  label,
  doc.layers[3],
  page
)

      vp = Layout::SketchUpModel.new(
        model.path,
        Geom::Bounds2d.new(
          Geom::Point2d.new(vx, vy),
          Geom::Point2d.new(vx + 4.0, vy + 2.5)
        )
      )

      scene_index = vp.scenes.index(scene_name)

      next unless scene_index

      vp.current_scene = scene_index
  

      if scene_name.end_with?("_PLAN")
        vp.scale = plan_scale

      elsif scene_name.end_with?("_ELEV")
        vp.scale = elev_scale

      elsif scene_name.end_with?("_ELEV_NO_DOORS")
        vp.scale = no_doors_scale
      end
      vp.preserve_scale_on_resize = true

      doc.add_entity(
        vp,
        doc.layers[3],
        page
      )

      puts "PLACED #{scene_name}"

    end

  end

end

    out_file = File.join(
      File.dirname(model.path),
      "AssemblyPackage.layout"
    )

    doc.save(out_file)

pdf_file = File.join(
  File.dirname(model.path),
  "AssemblyPackage.pdf"
)

doc.export(pdf_file)

puts "PDF CREATED:"
puts pdf_file

    UI.messagebox(
      "Created:\n#{out_file}"
    )

  rescue => e

    UI.messagebox(
      "ERROR:\n#{e.message}"
    )

    puts e.message
    puts e.backtrace

  end

end

  file_loaded(__FILE__)

end

end
end