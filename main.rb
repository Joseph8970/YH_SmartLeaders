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

  # Combined bounding box
  combined_bb = Geom::BoundingBox.new
  sel.each { |cab| combined_bb.add(cab.bounds.min, cab.bounds.max) }

  bb_min_z  = combined_bb.min.z
  bb_max_z  = combined_bb.max.z
  mid_z_in  = (((bb_min_z + bb_max_z) / 2.0) / 1.0.inch).round(2)

  # Detect base vs upper split: assume midpoint of full Z range
  split_z   = (bb_min_z + bb_max_z) / 2.0
  base_mid  = (((bb_min_z + split_z) / 2.0) / 1.0.inch).round(2)
  upper_mid = (((split_z + bb_max_z) / 2.0) / 1.0.inch).round(2)

  cab_names = sel.map(&:name).join(', ')

  # ── Step 1: Scene prefix + section heights ──────────────────────────
  prompts  = [
    'Scene name (e.g. A, B, KC)',
    'Base section cut height (inches)',
    'Upper section cut height (inches)',
    'Number of vertical sections'
  ]
  defaults = ['A', base_mid.to_s, upper_mid.to_s, '1']
  result   = UI.inputbox(prompts, defaults, 'Cabinet Scene Settings')
  return unless result

  prefix       = result[0].to_s.strip.upcase
  base_cut_z   = result[1].to_f.inch
  upper_cut_z  = result[2].to_f.inch
  num_vsections = result[3].to_i.clamp(0, 10)

  if prefix.empty?
    UI.messagebox("Please enter a valid scene name.")
    return
  end

  # ── Step 2: Vertical section targets ────────────────────────────────
  vsection_targets = []

  if num_vsections > 0
    v_prompts  = (1..num_vsections).map { |i| "Section #{i} — cabinet name" }
    v_defaults = (1..num_vsections).map { |i| sel[i - 1]&.name.to_s }
    v_result   = UI.inputbox(v_prompts, v_defaults, 'Vertical Section Targets')
    return unless v_result
    vsection_targets = v_result.map(&:to_s)
  end

  model.start_operation("Generate Cabinet Scenes", true)

  # Ensure scene tags exist
  tag_elev        = model.layers["TAG_ASM_ELEV"]          || model.layers.add("TAG_ASM_ELEV")
  tag_no_doors    = model.layers["TAG_ASM_ELEV_NO_DOORS"] || model.layers.add("TAG_ASM_ELEV_NO_DOORS")
  tag_3d          = model.layers["TAG_ASM_3D"]            || model.layers.add("TAG_ASM_3D")
  tag_3d_no_doors = model.layers["TAG_ASM_3D_NO_DOORS"]   || model.layers.add("TAG_ASM_3D_NO_DOORS")
  tag_section     = model.layers["TAG_ASM_SECTION"]       || model.layers.add("TAG_ASM_SECTION")

  doors_tag   = model.layers["TAG_DOORS"]
  drawers_tag = model.layers["TAG_DRAWERS"]

  view   = model.active_view
  cam    = view.camera
  center = combined_bb.center

  def self.make_scene(model, name, pages_ref)
    model.pages.erase(model.pages[name]) if model.pages[name]
    model.pages.add(name)
    puts "CREATED: #{name}"
  end

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
  tag_section.visible     = false

  make_scene(model, "#{prefix}_ELEV", nil)

  # ── ELEV_NO_DOORS ────────────────────────────────────────────────────
  doors_tag.visible   = false if doors_tag
  drawers_tag.visible = false if drawers_tag
  tag_elev.visible        = false
  tag_no_doors.visible    = true
  tag_3d.visible          = false
  tag_3d_no_doors.visible = false
  tag_section.visible     = false

  make_scene(model, "#{prefix}_ELEV_NO_DOORS", nil)

  # ── 3D ───────────────────────────────────────────────────────────────
  cam.perspective = true
  cam.set(
    center.offset(Geom::Vector3d.new(-1, -1, 0.6).normalize, 5000),
    center, Z_AXIS
  )
  view.zoom_extents

  doors_tag.visible   = true if doors_tag
  drawers_tag.visible = true if drawers_tag
  tag_elev.visible        = false
  tag_no_doors.visible    = false
  tag_3d.visible          = true
  tag_3d_no_doors.visible = false
  tag_section.visible     = false

  make_scene(model, "#{prefix}_3D", nil)

  # ── 3D_NO_DOORS ──────────────────────────────────────────────────────
  doors_tag.visible   = false if doors_tag
  drawers_tag.visible = false if drawers_tag
  tag_elev.visible        = false
  tag_no_doors.visible    = false
  tag_3d.visible          = false
  tag_3d_no_doors.visible = true
  tag_section.visible     = false

  make_scene(model, "#{prefix}_3D_NO_DOORS", nil)

  # ── SECTION_BASE (horizontal cut, top-down view) ──────────────────────
  cam.perspective = false

  # Each section plane on its own tag so scenes control visibility
  tag_sec_base  = model.layers["TAG_SEC_#{prefix}_BASE"]  || model.layers.add("TAG_SEC_#{prefix}_BASE")
  tag_sec_upper = model.layers["TAG_SEC_#{prefix}_UPPER"] || model.layers.add("TAG_SEC_#{prefix}_UPPER")

  model.entities.grep(Sketchup::SectionPlane).each { |sp|
    sp.erase! if sp.get_attribute('YH_SMART_LEADERS', 'section') == "#{prefix}_BASE" && sp.valid?
  }
  base_sp = model.entities.add_section_plane([center.x, center.y, base_cut_z], [0, 0, -1])
  base_sp.set_attribute('YH_SMART_LEADERS', 'section', "#{prefix}_BASE")
  base_sp.layer = tag_sec_base
  base_sp.activate

  cam.set(
    Geom::Point3d.new(center.x, center.y, base_cut_z + 5000),
    Geom::Point3d.new(center.x, center.y, base_cut_z),
    Y_AXIS
  )
  view.zoom_extents

  doors_tag.visible   = true if doors_tag
  drawers_tag.visible = true if drawers_tag
  tag_elev.visible        = false
  tag_no_doors.visible    = false
  tag_3d.visible          = false
  tag_3d_no_doors.visible = false
  tag_section.visible     = true
  tag_sec_base.visible    = true
  tag_sec_upper.visible   = false

  begin; model.rendering_options['DisplaySectionCuts'] = true; rescue; end

  make_scene(model, "#{prefix}_SECTION_BASE", nil)

  # ── SECTION_UPPER (horizontal cut, top-down view) ─────────────────────
  model.entities.grep(Sketchup::SectionPlane).each { |sp|
    sp.erase! if sp.get_attribute('YH_SMART_LEADERS', 'section') == "#{prefix}_UPPER" && sp.valid?
  }
  upper_sp = model.entities.add_section_plane([center.x, center.y, upper_cut_z], [0, 0, -1])
  upper_sp.set_attribute('YH_SMART_LEADERS', 'section', "#{prefix}_UPPER")
  upper_sp.layer = tag_sec_upper
  upper_sp.activate

  cam.set(
    Geom::Point3d.new(center.x, center.y, upper_cut_z + 5000),
    Geom::Point3d.new(center.x, center.y, upper_cut_z),
    Y_AXIS
  )
  view.zoom_extents

  tag_section.visible   = true
  tag_sec_base.visible  = false
  tag_sec_upper.visible = true

  begin; model.rendering_options['DisplaySectionCuts'] = true; rescue; end

  make_scene(model, "#{prefix}_SECTION_UPPER", nil)

  # Hide both horizontal section planes after their scenes
  tag_sec_base.visible  = false
  tag_sec_upper.visible = false

  # ── VERTICAL SECTIONS (one per targeted cabinet) ──────────────────────
  vsection_targets.each_with_index do |cab_name, i|

    target_cab = sel.find { |c| c.name == cab_name }
    unless target_cab
      puts "Vertical section #{i + 1}: cabinet '#{cab_name}' not found, skipping"
      next
    end

    cab_center = target_cab.bounds.center
    tag_sec_v  = model.layers["TAG_SEC_#{prefix}_V#{i + 1}"] ||
                 model.layers.add("TAG_SEC_#{prefix}_V#{i + 1}")

    vkey = "#{prefix}_V#{i + 1}"
    model.entities.grep(Sketchup::SectionPlane).each { |sp|
      sp.erase! if sp.get_attribute('YH_SMART_LEADERS', 'section') == vkey && sp.valid?
    }
    vsp = model.entities.add_section_plane([cab_center.x, cab_center.y, cab_center.z], [1, 0, 0])
    vsp.set_attribute('YH_SMART_LEADERS', 'section', vkey)
    vsp.layer = tag_sec_v
    vsp.activate

    cam.perspective = false
    cam.set(
      Geom::Point3d.new(cab_center.x - 5000, cab_center.y, center.z),
      Geom::Point3d.new(cab_center.x, cab_center.y, center.z),
      Z_AXIS
    )
    view.zoom_extents

    # Hide all other section tags, show only this one
    tag_sec_base.visible  = false
    tag_sec_upper.visible = false
    vsection_targets.each_with_index { |_, j|
      t = model.layers["TAG_SEC_#{prefix}_V#{j + 1}"]
      t.visible = (j == i) if t
    }
    tag_section.visible = true

    begin; model.rendering_options['DisplaySectionCuts'] = true; rescue; end

    make_scene(model, "#{prefix}_SECTION_V#{i + 1}", nil)

  end

  # Restore visibility
  doors_tag.visible   = true if doors_tag
  drawers_tag.visible = true if drawers_tag

  model.commit_operation

  total = 4 + 2 + vsection_targets.size
  UI.messagebox("#{total} scenes created for prefix '#{prefix}'.")

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


  # Raw projection of a world point to paper coords (no bounds check).
  def self.proj_x(world_pt, cam_target, vp_cx, scale_denom)
    vp_cx + (world_pt.x - cam_target.x) / scale_denom
  end

  def self.proj_y_elev(world_pt, cam_target, vp_cy, scale_denom)
    vp_cy - (world_pt.z - cam_target.z) / scale_denom
  end

  # Classify a part name into a category symbol.
  def self.part_cat(raw)
    n = raw.to_s.upcase.sub(/^\d+_/, '')
    return :door   if n.start_with?('DR')
    return :drawer if n.start_with?('DW')
    return :vs     if n.start_with?('VS')
    return :tp     if n.start_with?('TP')
    return :sh     if n.start_with?('SH')
    return :bk     if n.start_with?('BK')
    return :bp     if n.start_with?('BP')
    return :lp     if n.start_with?('LP')
    return :rp     if n.start_with?('RP')
    return :st     if n.start_with?('ST')
    return :b      if n =~ /^B\d*$/
    :other
  end

  ELEV_SHOW    = %i[door drawer vs].freeze
  NO_DOOR_SHOW = %i[tp sh bk bp lp rp st b].freeze

  # Add Layout::Label leaders for visible parts in a scene viewport.
  def self.add_layout_leaders(doc, page, layer, scene_name,
                               vp_x, vp_y, vp_w, vp_h,
                               cabinets, scale_denom, combined_bb,
                               leader_vert: 0.35, leader_horiz: 0.75)
    return [] if scene_name =~ /_3D(_NO_DOORS)?$/

    vp_cx      = vp_x + vp_w / 2.0
    vp_cy      = vp_y + vp_h / 2.0
    cam_target = combined_bb.center
    is_elev         = scene_name =~ /_ELEV$/ ? true : false
    is_elev_no_door = scene_name.include?('ELEV_NO_DOORS')
    is_section_h    = scene_name =~ /_SECTION_(BASE|UPPER)$/

    # text_w is calculated per-part below based on name length
    text_h     = 0.20   # slightly taller for one line of text
    labels     = []
    placed_pts = []

    cabinets.each do |cab|
      t = cab.transformation

      # Project this cabinet's bounding box onto paper so we can clamp leaders inside it
      cab_min_px = vp_cx + (cab.bounds.min.x - cam_target.x) / scale_denom
      cab_max_px = vp_cx + (cab.bounds.max.x - cam_target.x) / scale_denom
      if is_section_h
        cab_top_py = vp_cy - (cab.bounds.max.y - cam_target.y) / scale_denom
        cab_bot_py = vp_cy - (cab.bounds.min.y - cam_target.y) / scale_denom
      else
        cab_top_py = vp_cy - (cab.bounds.max.z - cam_target.z) / scale_denom
        cab_bot_py = vp_cy - (cab.bounds.min.z - cam_target.z) / scale_denom
      end
      # Ensure min < max (mirrored cabinets can swap them)
      cab_min_px, cab_max_px = [cab_min_px, cab_max_px].minmax
      cab_top_py, cab_bot_py = [cab_top_py, cab_bot_py].minmax

      cab.entities.each do |ent|
        next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)

        part_name = ent.is_a?(Sketchup::ComponentInstance) ? ent.definition.name : ent.name
        next if part_name.to_s.strip.empty?

        cat = part_cat(part_name)

        # ── Scene-type visibility filter ──────────────────────────────────
        if is_elev
          next unless ELEV_SHOW.include?(cat)
        elsif is_elev_no_door
          next unless NO_DOOR_SHOW.include?(cat)
        else
          # Sections: skip doors/drawers
          next if %i[door drawer].include?(cat)
        end

        world_center = ent.bounds.center.transform(t)
        world_min    = ent.bounds.min.transform(t)
        world_max    = ent.bounds.max.transform(t)

        # Project component center
        if is_section_h
          px = vp_cx + (world_center.x - cam_target.x) / scale_denom
          py = vp_cy - (world_center.y - cam_target.y) / scale_denom
        else
          px = proj_x(world_center, cam_target, vp_cx, scale_denom)
          py = proj_y_elev(world_center, cam_target, vp_cy, scale_denom)
        end

        # Skip if outside viewport
        next if px < vp_x || px > vp_x + vp_w || py < vp_y || py > vp_y + vp_h

        # ── Leader position rules ─────────────────────────────────────────
        # Explicit L-shaped path: arrow → elbow (vertical) → text connection (horizontal)
        arrow_px = px
        arrow_py = py

        right_edge_px = proj_x(world_max, cam_target, vp_cx, scale_denom)
        left_edge_px  = proj_x(world_min, cam_target, vp_cx, scale_denom)

        # Dynamic text box width: ~0.068" per character, minimum 0.40"
        text_w = [part_name.to_s.length * 0.068 + 0.04, 0.40].max

        elbow_drop  = leader_vert    # vertical segment length (user-configurable)
        horiz_run   = leader_horiz   # horizontal segment length (user-configurable)
        arrow_inset = 0.05           # arrow inset from the divider edge into the door

        # path_pts: [arrow, elbow, text_connection] — set per part type below
        path_pts = nil

        case cat
        when :door
          is_left_door = part_name =~ /L\d*$/i ||
                         (!part_name.match?(/R\d*$/i) && world_center.x < cam_target.x)

          elbow_y = arrow_py + elbow_drop   # elbow is BELOW the arrow

          if is_left_door
            # Arrow inset into left door; leader goes DOWN then LEFT by horiz_run.
            arrow_px    = right_edge_px - arrow_inset
            elbow_pt_x  = arrow_px
            text_conn_x = arrow_px - horiz_run          # left end of horizontal run
            tx          = text_conn_x - text_w          # text box left of connection
            ty          = elbow_y - text_h / 2.0
            path_pts = [
              [arrow_px,    arrow_py],
              [elbow_pt_x,  elbow_y],
              [text_conn_x, elbow_y]
            ]
          else
            # Arrow inset into right door; leader goes DOWN then RIGHT by horiz_run.
            arrow_px    = left_edge_px + arrow_inset
            elbow_pt_x  = arrow_px
            text_conn_x = arrow_px + horiz_run          # right end of horizontal run
            tx          = text_conn_x                   # text box right of connection
            ty          = elbow_y - text_h / 2.0
            path_pts = [
              [arrow_px,    arrow_py],
              [elbow_pt_x,  elbow_y],
              [text_conn_x, elbow_y]
            ]
          end

        when :drawer
          # Arrow at drawer centre; leader goes LEFT then TEXT (single horizontal).
          tx = px - text_w - 0.20
          ty = py - text_h / 2.0
          path_pts = [
            [arrow_px, arrow_py],
            [tx + text_w, arrow_py]
          ]

        else
          # Structural parts: leader goes DOWN then to the less-crowded side.
          is_right_side = world_center.x >= cam_target.x
          elbow_y = arrow_py + elbow_drop
          if is_right_side
            text_conn_x = arrow_px + horiz_run
            tx = text_conn_x
            path_pts = [
              [arrow_px, arrow_py],
              [arrow_px, elbow_y],
              [text_conn_x, elbow_y]
            ]
          else
            text_conn_x = arrow_px - horiz_run
            tx = text_conn_x - text_w
            path_pts = [
              [arrow_px, arrow_py],
              [arrow_px, elbow_y],
              [text_conn_x, elbow_y]
            ]
          end
          ty = elbow_y - text_h / 2.0
        end

        # Clamp text box to stay inside this cabinet's projected bounds
        pad = 0.03
        tx  = [[tx, cab_min_px + pad].max, cab_max_px - text_w - pad].min
        ty  = [[ty, cab_top_py + pad].max, cab_bot_py - text_h - pad].min

        # After clamping tx, fix the path's last point so it still touches the text box.
        # For left-door / structural-left: connection is at right edge of text box (tx + text_w).
        # For right-door / structural-right / drawer: connection is at left edge (tx).
        if path_pts && path_pts.length >= 2
          last = path_pts.last
          if last[0] < arrow_px   # leader goes LEFT → connect to right edge of text box
            path_pts[-1] = [tx + text_w, last[1]]
          else                    # leader goes RIGHT → connect to left edge of text box
            path_pts[-1] = [tx, last[1]]
          end
        end

        # Skip near-duplicate text positions
        next if placed_pts.any? { |ex, ey| (ex - tx).abs < 0.04 && (ey - ty).abs < 0.04 }
        placed_pts << [tx, ty]

        target_pt   = Geom::Point2d.new(arrow_px, arrow_py)
        text_bounds = Geom::Bounds2d.new(tx, ty, text_w, text_h)

        begin
          label = Layout::Label.new(
            part_name,
            Layout::Label::LEADER_LINE_TYPE_TWO_SEGMENT,
            target_pt,
            text_bounds
          )

          # Override the auto-generated leader with an explicit L-shaped path
          if path_pts && path_pts.length >= 2
            begin
              pts = path_pts.map { |x, y| Geom::Point2d.new(x, y) }
              lpath = Layout::Path.new(pts[0], pts[1])
              pts[2..].each { |pt| lpath.append_point(pt) } if pts.length > 2
              label.leader_line = lpath
            rescue => pe
              puts "  leader_line= err #{part_name}: #{pe.message}"
            end
          end

          doc.add_entity(label, layer, page)
          labels << label
          puts "  LABEL: #{part_name} @ arrow(#{arrow_px.round(2)},#{arrow_py.round(2)})"
        rescue => e
          puts "  Label err #{part_name}: #{e.message}"
        end
      end
    end

    labels
  end

  def self.generate_assembly_package

    model = Sketchup.active_model

    if model.path.empty?
      UI.messagebox("Save the SketchUp model first.")
      return
    end

    # ── Step 1: prefix + scale + leaders option + leader segment sizes ──
    # ── Leader geometry (paper inches) — edit these two values to tune leaders ──
    leader_vert  = 0.15   # vertical segment: arrow → elbow
    leader_horiz = 0.15   # horizontal segment: elbow → text

    result = UI.inputbox(
      ['Scene prefix (e.g. A, B, KC)',
       'Scale denominator (e.g. 20 for 1:20, 48 for 1/4"=1\')',
       'Add part leaders? (Y / N)'],
      ['A', '20', 'Y'],
      'Assembly Package'
    )
    return unless result

    prefix      = result[0].to_s.strip.upcase
    scale_denom = result[1].to_f
    add_leaders = result[2].to_s.strip.upcase.start_with?('Y')

    if scale_denom <= 0
      UI.messagebox("Invalid scale.")
      return
    end
    scale = 1.0 / scale_denom

    # ── Step 2: find matching scenes + let user pick which to include ───
    all_scenes = model.pages.map(&:name).select { |n| n.start_with?("#{prefix}_") }
    if all_scenes.empty?
      UI.messagebox("No scenes found for prefix '#{prefix}'.\nGenerate assembly scenes first.")
      return
    end

    sel_result = UI.inputbox(
      all_scenes,
      Array.new(all_scenes.size, 'Y'),
      "Select Scenes to Include (Y = yes, N = no)"
    )
    return unless sel_result

    scene_names = all_scenes.select.with_index { |_, i| sel_result[i].to_s.strip.upcase.start_with?('Y') }
    if scene_names.empty?
      UI.messagebox("No scenes selected.")
      return
    end

    # ── Step 3: template ────────────────────────────────────────────────
    template_path = UI.openpanel("Select Layout Template", "", "Layout Files|*.layout|")
    return unless template_path

    # ── Step 4: output path ─────────────────────────────────────────────
    default_name = File.basename(model.path, '.skp') + "_#{prefix}.layout"
    output_path  = UI.savepanel("Save Layout Package", File.dirname(model.path), default_name)
    return unless output_path
    output_path += '.layout' unless output_path.end_with?('.layout')

    # ── Step 5: build Layout document ───────────────────────────────────
    begin
      doc   = Layout::Document.open(template_path)
      page  = doc.pages.first
      layer = doc.layers.first

      # Compute model bounding box from all top-level groups
      all_groups = model.entities.grep(Sketchup::Group)
      combined_bb = Geom::BoundingBox.new
      all_groups.each { |g| combined_bb.add(g.bounds.min, g.bounds.max) }
      bb_w = (combined_bb.max.x - combined_bb.min.x).to_f
      bb_h = (combined_bb.max.z - combined_bb.min.z).to_f
      bb_d = (combined_bb.max.y - combined_bb.min.y).to_f
      pad  = 1.15

      gap    = 0.5
      margin = 1.0
      cur_x  = margin
      cur_y  = margin
      row_h  = 0.0
      page_w = doc.page_info.width - margin * 2

      placed_vps = []  # track positions for leader placement

      scene_names.each do |scene_name|
        is_3d        = scene_name =~ /_3D(_NO_DOORS)?$/
        is_section_h = scene_name =~ /_SECTION_(BASE|UPPER)$/
        is_section_v = scene_name =~ /_SECTION_V/

        if is_3d
          vp_w = 5.0
          vp_h = 4.0
        elsif is_section_h
          vp_w = [(bb_w * pad / scale_denom), 2.0].max
          vp_h = [(bb_d * pad / scale_denom), 2.0].max
        elsif is_section_v
          vp_w = [(bb_d * pad / scale_denom), 2.0].max
          vp_h = [(bb_h * pad / scale_denom), 2.0].max
        else
          vp_w = [(bb_w * pad / scale_denom), 2.0].max
          vp_h = [(bb_h * pad / scale_denom), 2.0].max
        end

        if cur_x + vp_w > margin + page_w && cur_x > margin
          cur_y += row_h + gap
          cur_x  = margin
          row_h  = 0.0
        end

        bounds = Geom::Bounds2d.new(
          Geom::Point2d.new(cur_x, cur_y),
          Geom::Point2d.new(cur_x + vp_w, cur_y + vp_h)
        )

        vp = Layout::SketchUpModel.new(model.path, bounds)
        scene_idx = vp.scenes.index(scene_name)
        unless scene_idx
          puts "SKIP: #{scene_name} not found"
          next
        end

        vp.current_scene = scene_idx
        unless is_3d
          begin
            vp.scale = scale
            vp.preserve_scale_on_resize = true
          rescue => e
            puts "Scale skipped for #{scene_name}: #{e.message}"
          end
        end

        doc.add_entity(vp, layer, page)
        puts "PLACED: #{scene_name} (#{vp_w.round(2)}\" × #{vp_h.round(2)}\")"

        placed_vps << { scene: scene_name, vp: vp,
                        x: cur_x, y: cur_y, w: vp_w, h: vp_h }

        cur_x += vp_w + gap
        row_h  = [row_h, vp_h].max
      end

      # ── Phase 3: add part leaders and group with viewport ────────────────
      if add_leaders
        placed_vps.each do |info|
          next if info[:scene] =~ /_3D(_NO_DOORS)?$/

          labels = add_layout_leaders(
            doc, page, layer,
            info[:scene], info[:x], info[:y], info[:w], info[:h],
            all_groups, scale_denom, combined_bb,
            leader_vert: leader_vert, leader_horiz: leader_horiz
          )

          # Group viewport + labels so they move together
          entities_to_group = [info[:vp]] + labels
          unless entities_to_group.empty?
            begin
              grp = Layout::Group.new(entities_to_group)
              doc.add_entity(grp, layer, page)
              # Move original vp and labels out of doc (they're now inside group)
            rescue
              # Grouping not supported this way — entities stay ungrouped
            end
          end
        end
      end

      doc.save(output_path)

      # Open in Layout
      system("start \"\" \"#{output_path}\"")

      UI.messagebox("#{scene_names.size} viewports placed at 1:#{scale_denom.to_i} scale.\nFile: #{output_path}")

    rescue => e
      UI.messagebox("ERROR creating Layout file:\n#{e.message}")
      puts e.message
      puts e.backtrace.first(10).join("\n")
    end

  end

  file_loaded(__FILE__)

end

end
end