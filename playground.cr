require "./dendro_multi_era"
require "./helpers/util"

# Set variables here
add_core = true
color_id = 0
number = 1
previous_cores = Util.js_to_json <<-JSON
[{"cp": [43, 9], "age": 17, "life": 24, "max_r": 8},
 {"cp": [33, 37], "age": 15, "life": 23, "max_r": 6},
 {"cp": [15, 18], "age": 14, "life": 15, "max_r": 6},
 {"cp": [91, 57], "age": 9, "life": 25, "max_r": 5},
 {"cp": [56, 39], "age": 5, "life": 17, "max_r": 8},
 {"cp": [59, 68], "age": 4, "life": 18, "max_r": 5}]
JSON

# This part builds the Dendro
dendro = Dendro.new(
  seed: number,
  color: color_id,
  previous_cores: previous_cores,
  add_core: add_core
)

# This part writes the resulting SVG file to the 'playground' folder
File.write(Util.svg_file_name(number), dendro.to_svg)
