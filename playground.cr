require "./dendro"
require "./helpers/util"

# (6..17).each do |i|
[7].each do |i|
  # Set variables here
  add_core = true
  color_id = i
  number = i
  previous_cores = Util.js_to_json <<-JSON
   [{"cp": [82, 19], "age": 21, "life": 22, "max_r": 6},
    {"cp": [20, 46], "age": 20, "life": 22, "max_r": 6},
    {"cp": [99, 46], "age": 18, "life": 23, "max_r": 8},
    {"cp": [47, 63], "age": 7, "life": 22, "max_r": 5},
    {"cp": [48, 80], "age": 6, "life": 19, "max_r": 5},
    {"cp": [22, 73], "age": 3, "life": 19, "max_r": 6}]
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
end
