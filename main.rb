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

  prompts = [
    'Leader Length (inches)  — how long each leader line is',
    'Stagger Step (inches)   — gap between overlapping labels'
  ]

  defaults = [
    s[:leader_offset],
    s[:text_offset]
  ]

  values = UI.inputbox(
    prompts,
    defaults,
    'Smart Leaders Settings'
  )

  return unless values

  model.set_attribute(DICT, 'leader_offset', values[0].to_f)
  model.set_attribute(DICT, 'text_offset',   values[1].to_f)

  UI.messagebox('Settings saved. Regenerate leaders to apply.')

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

  # Delete all previously generated leaders (identified by custom attribute)
  model.entities.select { |e|
    e.is_a?(Sketchup::Text) &&
    e.get_attribute('YH_SMART_LEADERS', 'scene') == scene_name
  }.each { |e| e.erase! if e.valid? }

  groups.each do |cabinet|

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

    # Text entities must live at model top level to display correctly
    ents = model.entities

    cabinet_parts =
      cabinet.entities.grep(Sketchup::ComponentInstance)
puts "PART COUNT = #{cabinet_parts.size}"
cabinet_parts.each { |p| puts p.definition.name }



    # Separate stagger counters per direction so leaders stay straight
    stagger_x_pos  = 0  # parts on right side
    stagger_x_neg  = 0  # parts on left side
    stagger_y_pos  = 0  # parts at front
    stagger_y_neg  = 0  # parts at back
    stagger_z_pos  = 0  # parts at top
    stagger_z_neg  = 0  # parts at bottom

    cabinet_parts.each do |part|

  # Skip hidden components or components on hidden layers
  next if part.hidden?
  next if part.layer && !part.layer.visible?

  part_name = part.definition.name.to_s.upcase

  bb = part.bounds

  s = settings

  offset    = s[:leader_offset].inch   # controls leader line length
  text_gap  = s[:text_offset].inch     # controls stagger step between labels
  step      = text_gap                 # stagger uses Text Offset setting

  cab_center  = cabinet.bounds.center
  part_center = bb.center

  part_w = (bb.max.x - bb.min.x).abs
  part_h = (bb.max.z - bb.min.z).abs
  part_d = (bb.max.y - bb.min.y).abs

  if scene_name.include?('PLAN')

    dx = part_center.x - cab_center.x
    dy = part_center.y - cab_center.y

    if dx.abs >= dy.abs
      if dx >= 0
        # RIGHT side panel → anchor inner left face, leader goes left
        center  = Geom::Point3d.new(bb.min.x, (bb.min.y + bb.max.y) / 2, bb.max.z)
        dir     = X_AXIS.reverse
        text_pt = center.offset(dir, offset + stagger_x_pos * step)
        stagger_x_pos += 1
      else
        # LEFT side panel → anchor inner right face, leader goes right
        center  = Geom::Point3d.new(bb.max.x, (bb.min.y + bb.max.y) / 2, bb.max.z)
        dir     = X_AXIS
        text_pt = center.offset(dir, offset + stagger_x_neg * step)
        stagger_x_neg += 1
      end
    else
      if dy >= 0
        # FRONT part → anchor inner back face, leader goes back
        center  = Geom::Point3d.new((bb.min.x + bb.max.x) / 2, bb.min.y, bb.max.z)
        dir     = Y_AXIS.reverse
        text_pt = center.offset(dir, offset + stagger_y_pos * step)
        stagger_y_pos += 1
      else
        # BACK part → anchor inner front face, leader goes forward
        center  = Geom::Point3d.new((bb.min.x + bb.max.x) / 2, bb.max.y, bb.max.z)
        dir     = Y_AXIS
        text_pt = center.offset(dir, offset + stagger_y_neg * step)
        stagger_y_neg += 1
      end
    end

  elsif scene_name.include?('ELEV')

    dx  = part_center.x - cab_center.x
    dz  = part_center.z - cab_center.z
    cab_w = (cabinet.bounds.max.x - cabinet.bounds.min.x).abs
    cab_h = (cabinet.bounds.max.z - cabinet.bounds.min.z).abs

    # Full-span parts (BK, TP, B) span >80% of cabinet width → vertical leader at a corner offset
    is_full_span = part_w >= cab_w * 0.8

    if is_full_span
      # Anchor at top-left quarter, leader goes up into open space
      anchor_x = bb.min.x + (bb.max.x - bb.min.x) * 0.25
      if dz >= 0
        center  = Geom::Point3d.new(anchor_x, bb.min.y, bb.min.z)
        dir     = Z_AXIS.reverse
      else
        center  = Geom::Point3d.new(anchor_x, bb.min.y, bb.max.z)
        dir     = Z_AXIS
      end
      text_pt = center.offset(dir, offset + stagger_z_neg * step)
      stagger_z_neg += 1

    elsif part_w < part_h
      # TALL/VERTICAL part (side panel LP, RP) → horizontal leader at mid-height inward
      if dx >= 0
        # Right panel → anchor inner left face, leader goes left
        center  = Geom::Point3d.new(bb.min.x, bb.min.y, (bb.min.z + bb.max.z) / 2)
        text_pt = center.offset(X_AXIS.reverse, offset + stagger_x_pos * step)
        stagger_x_pos += 1
      else
        # Left panel → anchor inner right face, leader goes right
        center  = Geom::Point3d.new(bb.max.x, bb.min.y, (bb.min.z + bb.max.z) / 2)
        text_pt = center.offset(X_AXIS, offset + stagger_x_neg * step)
        stagger_x_neg += 1
      end

    else
      # WIDE/HORIZONTAL part (shelf, stretcher) → vertical leader
      # Alternate anchor X between 1/4 and 3/4 width so labels spread across cabinet
      if stagger_z_pos.even?
        anchor_x = bb.min.x + (bb.max.x - bb.min.x) * 0.25
      else
        anchor_x = bb.min.x + (bb.max.x - bb.min.x) * 0.75
      end

      if dz >= 0
        # Top half → leader goes down into compartment below
        center  = Geom::Point3d.new(anchor_x, bb.min.y, bb.min.z)
        dir     = Z_AXIS.reverse
      else
        # Bottom half → leader goes up into compartment above
        center  = Geom::Point3d.new(anchor_x, bb.min.y, bb.max.z)
        dir     = Z_AXIS
      end
      text_pt = center.offset(dir, offset + step)
      stagger_z_pos += 1
    end

  end

next unless center
  next unless text_pt

  # Transform points from cabinet local space to world space
  t = cabinet.transformation
  world_center  = center.transform(t)
  world_text_pt = text_pt.transform(t)

  # Native SketchUp leader: arrow at component, text at world text position
  leader_vector = world_center.vector_to(world_text_pt)
  txt = ents.add_text(part_name, world_center, leader_vector)
  if txt
    # Stamp with scene name so we can find and delete it later
    txt.set_attribute('YH_SMART_LEADERS', 'scene', scene_name)
    # Assign to scene tag so scene visibility controls which leaders show
    txt.layer = leader_tag
  end

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

  # Delete all previously generated leaders across all scenes
  to_erase = model.entities.select { |e|
    e.is_a?(Sketchup::Text) &&
    e.get_attribute('YH_SMART_LEADERS', 'scene')
  }
  to_erase.each { |e| e.erase! if e.valid? }

  # Use current selection if groups are selected, otherwise find all cabinets
  selected = model.selection.grep(Sketchup::Group)

  if selected.empty?
    UI.messagebox('Select one or more cabinet groups first.')
    model.abort_operation
    return
  end

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

cmd_cab_scenes = UI::Command.new('Generate Cabinet Scenes') {
  self.generate_assembly_scenes
}
cmd_cab_scenes.tooltip = 'Generate Cabinet Scenes — select cabinet groups first'
cmd_cab_scenes.small_icon = File.join(__dir__, 'icons', 'generate.svg')
cmd_cab_scenes.large_icon = File.join(__dir__, 'icons', 'generate.svg')

cmd_cab_leaders = UI::Command.new('Generate Cabinet Leaders & Dimensions') {
  self.generate_assembly_leaders
}
cmd_cab_leaders.tooltip = 'Generate leaders and W×H×D dimensions for all cabinet scenes'
cmd_cab_leaders.small_icon = File.join(__dir__, 'icons', 'update.svg')
cmd_cab_leaders.large_icon = File.join(__dir__, 'icons', 'update.svg')

toolbar.add_item(cmd_generate)
toolbar.add_item(cmd_update)
toolbar.add_item(cmd_settings)
toolbar.add_item(cmd_cab_scenes)
toolbar.add_item(cmd_cab_leaders)

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
  sel   = model.selection.grep(Sketchup::Group)

  if sel.empty?
    UI.messagebox("Select one or more cabinet groups first.")
    return
  end

  # Ask user for a scene prefix (e.g. A, B, KC)
  result = UI.inputbox(
    ['Scene name (e.g. A, B, KC)'],
    ['A'],
    'Cabinet Scene Name'
  )
  return unless result

  prefix = result[0].to_s.strip.upcase
  if prefix.empty?
    UI.messagebox("Please enter a valid scene name.")
    return
  end

  model.start_operation("Generate Cabinet Scenes", true)

  # Ensure scene tags exist
  tag_elev        = model.layers["TAG_ASM_ELEV"]          || model.layers.add("TAG_ASM_ELEV")
  tag_no_doors    = model.layers["TAG_ASM_ELEV_NO_DOORS"] || model.layers.add("TAG_ASM_ELEV_NO_DOORS")
  tag_3d          = model.layers["TAG_ASM_3D"]            || model.layers.add("TAG_ASM_3D")
  tag_3d_no_doors = model.layers["TAG_ASM_3D_NO_DOORS"]   || model.layers.add("TAG_ASM_3D_NO_DOORS")

  doors_tag   = model.layers["TAG_DOORS"]
  drawers_tag = model.layers["TAG_DRAWERS"]

  view = model.active_view
  cam  = view.camera

  # Compute combined bounding box of all selected cabinets
  combined_bb = Geom::BoundingBox.new
  sel.each { |cab| combined_bb.add(cab.bounds.min, cab.bounds.max) }

  center = combined_bb.center

  # ── ELEV ────────────────────────────────────────────────────────────
  cam.perspective = false
  cam.set(center.offset(Y_AXIS.reverse, 5000), center, Z_AXIS)
  view.zoom_extents

  doors_tag.visible   = true if doors_tag
  drawers_tag.visible = true if drawers_tag
  tag_elev.visible        = true
  tag_no_doors.visible    = false
  tag_3d.visible          = false
  tag_3d_no_doors.visible = false

  elev_scene = "#{prefix}_ELEV"
  model.pages.erase(model.pages[elev_scene]) if model.pages[elev_scene]
  model.pages.add(elev_scene)
  puts "CREATED: #{elev_scene}"

  # ── ELEV_NO_DOORS ────────────────────────────────────────────────────
  doors_tag.visible   = false if doors_tag
  drawers_tag.visible = false if drawers_tag
  tag_elev.visible        = false
  tag_no_doors.visible    = true
  tag_3d.visible          = false
  tag_3d_no_doors.visible = false

  elev_nd_scene = "#{prefix}_ELEV_NO_DOORS"
  model.pages.erase(model.pages[elev_nd_scene]) if model.pages[elev_nd_scene]
  model.pages.add(elev_nd_scene)
  puts "CREATED: #{elev_nd_scene}"

  # ── 3D ───────────────────────────────────────────────────────────────
  cam.perspective = true
  cam.set(
    center.offset(Geom::Vector3d.new(-1, -1, 0.6).normalize, 5000),
    center,
    Z_AXIS
  )
  view.zoom_extents

  doors_tag.visible   = true if doors_tag
  drawers_tag.visible = true if drawers_tag
  tag_elev.visible        = false
  tag_no_doors.visible    = false
  tag_3d.visible          = true
  tag_3d_no_doors.visible = false

  scene_3d = "#{prefix}_3D"
  model.pages.erase(model.pages[scene_3d]) if model.pages[scene_3d]
  model.pages.add(scene_3d)
  puts "CREATED: #{scene_3d}"

  # ── 3D_NO_DOORS ──────────────────────────────────────────────────────
  doors_tag.visible   = false if doors_tag
  drawers_tag.visible = false if drawers_tag
  tag_elev.visible        = false
  tag_no_doors.visible    = false
  tag_3d.visible          = false
  tag_3d_no_doors.visible = true

  scene_3d_nd = "#{prefix}_3D_NO_DOORS"
  model.pages.erase(model.pages[scene_3d_nd]) if model.pages[scene_3d_nd]
  model.pages.add(scene_3d_nd)
  puts "CREATED: #{scene_3d_nd}"

  # Restore visibility
  doors_tag.visible   = true if doors_tag
  drawers_tag.visible = true if drawers_tag

  model.commit_operation

  UI.messagebox("4 scenes created: #{prefix}_ELEV, #{prefix}_ELEV_NO_DOORS, #{prefix}_3D, #{prefix}_3D_NO_DOORS")

end

# ── Dimensions: W × H × D on the cabinet bounding box ─────────────────────
def self.generate_dimensions(cabinet, ents, leader_tag)

  model = Sketchup.active_model
  t     = cabinet.transformation
  bb    = cabinet.bounds

  s      = settings
  offset = s[:leader_offset].inch

  # World-space corners
  min_w = bb.min.transform(t)
  max_w = bb.max.transform(t)

  # Width dimension (X axis) — placed below cabinet
  w_start = Geom::Point3d.new(min_w.x, min_w.y, min_w.z)
  w_end   = Geom::Point3d.new(max_w.x, min_w.y, min_w.z)
  w_mid   = Geom::Point3d.new((min_w.x + max_w.x) / 2, min_w.y, min_w.z - offset)
  width_in = ((max_w.x - min_w.x).abs / 1.0.inch).round(3)

  ents.add_line(w_start, w_end)
  txt = ents.add_text("W: #{width_in}\"", w_mid)
  if txt
    txt.set_attribute('YH_SMART_LEADERS', 'dim', true)
    txt.layer = leader_tag
  end

  # Height dimension (Z axis) — placed to the right of cabinet
  h_start = Geom::Point3d.new(max_w.x + offset, min_w.y, min_w.z)
  h_end   = Geom::Point3d.new(max_w.x + offset, min_w.y, max_w.z)
  h_mid   = Geom::Point3d.new(max_w.x + offset * 1.5, min_w.y, (min_w.z + max_w.z) / 2)
  height_in = ((max_w.z - min_w.z).abs / 1.0.inch).round(3)

  ents.add_line(h_start, h_end)
  txt = ents.add_text("H: #{height_in}\"", h_mid)
  if txt
    txt.set_attribute('YH_SMART_LEADERS', 'dim', true)
    txt.layer = leader_tag
  end

  # Depth dimension (Y axis) — placed below cabinet, offset from width
  d_start = Geom::Point3d.new(min_w.x, min_w.y, min_w.z - offset * 2)
  d_end   = Geom::Point3d.new(min_w.x, max_w.y, min_w.z - offset * 2)
  d_mid   = Geom::Point3d.new(min_w.x, (min_w.y + max_w.y) / 2, min_w.z - offset * 2.5)
  depth_in = ((max_w.y - min_w.y).abs / 1.0.inch).round(3)

  ents.add_line(d_start, d_end)
  txt = ents.add_text("D: #{depth_in}\"", d_mid)
  if txt
    txt.set_attribute('YH_SMART_LEADERS', 'dim', true)
    txt.layer = leader_tag
  end

end

def self.generate_assembly_leaders
  UI.messagebox("Leaders and dimensions are generated automatically in Layout.\nUse 'Generate Assembly Package' to create the Layout file.")
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