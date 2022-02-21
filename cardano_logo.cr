require "./dendro_logo"
require "./helpers/util"

# Set variables here
previous_cores = [[16, 6.5], [27, 4], [35, 3.5], [44, 2.75], [47.5, 2.2]]
  .map_with_index do |p, m|
    (0..5).map do |i|
      {p[0], p[1], Dendro::Geo.deg_to_rad(90 * (m % 2) + i * 60)}
    end
  end
  .flatten
  .map do |p|
    cp = Dendro::Geo.point_on_circle({50,50}, p[0], p[2])
    {:cp => {cp[0].to_i, cp[1].to_i},
     :age => 4,
     :life => 9,
     :max_r => (p[1] * 0.9).to_i}
  end
  .to_json

puts previous_cores
# This part builds the Dendro
dendro = Dendro.new(
  seed: 1,
  color: 0,
  previous_cores: previous_cores,
  add_core: false
)

# This part writes the resulting SVG file to the 'playground' folder
File.write(Util.svg_file_name(1), dendro.to_svg(30))
