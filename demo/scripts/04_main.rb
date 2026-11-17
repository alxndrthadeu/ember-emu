# encoding: utf-8
#
# Start: clean text (no outline or shadow) and the title screen.

begin
  Font.default_outline = false
  Font.default_shadow = false
rescue StandardError
end
Font.default_size = 22
Graphics.frame_rate = 60

$scene = TitleScene.new
# "Continuar" from Ember's auto state skips the title.
if defined?(EmberState) && EmberState.resume_slot && EmberState.resume_at_title && $demo_pending_state
  $scene = MapScene.new($demo_pending_state)
  $demo_pending_state = nil
end
$scene.main while $scene
