require "./dendro"
require "./helpers/util"

# Set variables here
add_core = true
color_id = 0
number = 1
previous_cores = Util.js_to_json <<-JSON
[
   {
      age: 1,
      cp: [
         48,
         11
      ],
      life: 21,
      max_r: 8
   }
]
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
