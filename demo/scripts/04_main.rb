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
$scene.main while $scene
