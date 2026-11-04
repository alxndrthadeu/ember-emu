# Ember preload: no Ruby warnings.
#
# Old fan games trip Ruby deprecation warnings every frame (Pokémon
# Ópalo calls Object#id ~300 times a second on Ruby 1.8). Each one is a
# write to stdout, which costs real time on a phone. A nil $VERBOSE
# silences warnings and nothing else; errors still surface.
$VERBOSE = nil
