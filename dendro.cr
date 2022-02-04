# DendroRithms (c) 2022 Wout Fierens - https://dendrorithms.com/
# License: AGPL v3 https://www.gnu.org/licenses/agpl-3.0.en.html
# Source code: https://github.com/wout/dendro/
# To run, install Crystal: https://crystal-lang.org/install/
# Or paste into the playground: https://play.crystal-lang.org/
# This code is written for Crystal 1.3 and has no dependendies.

require %(json)
require %(xml)

struct Dendro
  CORE_ANGLES    = (8..18)      # min/max number growth angles
  CORE_DIST      = 7.0          # min distance between cores
  CORE_LIFETIME  = (15..25)     # min/max lifetime of a core
  CORE_R_INIT    = 2.0          # initial core radius
  CORE_R_MAX     = (5..8)       # variable max core radius
  CORE_RATE      = {0.8, 1.5}   # min/max growth rate
  CORE_TRIES     = 500          # max tries to find new position
  FILL           = %(#111111)   # background colour
  LAYER_DIST     =  0.4         # distance between layers
  LAYER_FLOW     =  400         # the max number of layers
  LAYER_FALLOFF  =   60         # number of layers for spacing
  LAYER_MAX      =  0.5         # max usable layer distance
  LAYER_REDUCE   =   20         # flow reduction step per core
  LAYER_SMOOTH   = 0.15         # smoothing of bezier curve
  LAYER_SPACING  = {1.1, 0.8}   # start/end layer spacing
  POINT_DIST     = 1.25         # distance between layer points
  PREDICT_DIST   =  2.0         # predicted growth deactivation
  SECTOR_NUM     = 360 * 10     # growth deactivation sectors
  SIZE_DOC       = 4096         # document size for export
  SIZE_VB        =  100         # viewbox size
  STROKE_OPACITY = {0.85, 0.95} # min/max stroke opacity
  STROKE_WIDTH   = {0.12, 0.18} # min/max stroke width

  SECTOR_RES = 360 / SECTOR_NUM

  COLORS = {
    %(#BAF4DE), # 0: verdigris
    %(#FFFFFA), # 1: porcelain
    %(#CAEFF7), # 2: frost
    %(#DFEDAE), # 3: phosphor
    %(#DEDAF1), # 4: lilac
    %(#E5B7A5), # 5: copper
  }

  alias Point = Tuple(Float64, Float64)
  alias KeyPoint = Tuple(Int32, Float64)

  private getter color : Int32
  private getter previous_cores : Array(Core)
  private getter current_cores : Array(Core)
  private getter prng : Random::PCG32
  private getter seed : Int32

  def initialize(@seed, @color, previous_cores, add_core : Bool)
    @prng = Random.new(@seed)
    @previous_cores = Array(Core).from_json(previous_cores)
    @current_cores = evolve_cores(@previous_cores)
    add_new_core if @current_cores.empty?
    add_new_core if add_core
  end

  def to_svg : String
    to_svg(LAYER_FLOW - (number_of_cores - 1) * LAYER_REDUCE)
  end

  def to_svg(layer_flow : Int32) : String
    Svg.build(color, current_cores, prng, layer_flow)
  end

  def previous_cores_as_json : String
    previous_cores.to_json
  end

  def current_cores_as_json : String
    current_cores.to_json
  end

  def number_of_cores : Int32
    current_cores.size
  end

  private def evolve_cores(cs) : Array(Core)
    cs.compact_map do |c|
      c.evolve
      c unless c.dead?
    end
  end

  private def add_new_core : Void
    max_r = prng.rand(CORE_R_MAX).to_f
    if cp = Core.position(max_r, current_cores, prng)
      l = prng.rand(CORE_LIFETIME)
      core = Core.new(cp: cp, max_r: max_r, life: l, age: 1)
      current_cores << core
    end
  end

  struct Core
    include JSON::Serializable

    getter age : Int32
    @[JSON::Field(converter: Dendro::PointFromArray)]
    getter cp : Point
    getter life : Int32
    @[JSON::Field(converter: Dendro::FloatFromInt)]
    getter max_r : Float64

    @[JSON::Field(ignore: true)]
    getter growth = Array(Float64).new
    @[JSON::Field(ignore: true)]
    getter layers = Array(Array(Tuple(Float64, Float64))).new
    @[JSON::Field(ignore: true)]
    getter sectors = Array(Float64?).new(SECTOR_NUM, nil)

    def initialize(@cp, @max_r, @life, @age = 1)
    end

    def evolve
      @age += 1
    end

    def r
      pos = -Math.cos(age / life * Math::PI * 2) / 2 + 0.5
      CORE_R_INIT + pos * (max_r - CORE_R_INIT)
    end

    def dead?
      age > life
    end

    def self.position(r, cs, prng, i = 0) : Point?
      return if i >= CORE_TRIES
      p = Geo.random_point_on_circle(prng)
      overlapping?(cs, p, r) ? position(r, cs, prng, i + 1) : p
    end

    def self.overlapping?(cs, p, r) : Bool
      cs.any? do |c|
        Geo.point_distance(p, c.cp) <= r + c.max_r + CORE_DIST
      end
    end

    def self.growth_rates(prng) : Array(Float64)
      ks = key_points(prng.rand(CORE_ANGLES), 360, prng)
      Blend.key_points(ks, 360)
    end

    def self.key_points(n, t, prng) : Array(KeyPoint)
      s = t / n
      min, max = CORE_RATE
      (0..(n - 1)).map do |i|
        {(i * s + prng.rand(s)).to_i,
         (min + prng.rand(max - min)).round(2)}
      end
    end
  end

  module Layer
    extend self

    def build(cs, prng, layer_flow) : Void
      cs.each { |c| c.growth.concat(Core.growth_rates(prng)) }
      layer_flow.times do |l|
        cs.each do |core|
          r = core.r + scaled_dist(l)
          n = (Geo.r_to_length(r) / POINT_DIST).round
          core.layers << (0..(n - 1)).map do |i|
            build_point(core, r, n, i, prng)
          end
        end
        Deactivation.update(cs)
      end
    end

    def scaled_dist(i) : Float64
      s, e = LAYER_SPACING
      step = Blend.step(s, e, Blend.pos(i, LAYER_FALLOFF))
      LAYER_DIST * i * step
    end

    def build_point(c, r, n, i, prng) : Point
      rad = Geo.deg_to_rad(360 / n) * i
      rn = r + LAYER_DIST
      x, y = c.cp
      p = {x + rn * Math.cos(rad), y + rn * Math.sin(rad)}
      rn = next_radius(r, sector_angle(c.cp, p), c, prng)
      {(x + rn * Math.cos(rad)).round(1),
       (y + rn * Math.sin(rad)).round(1)}
    end

    def next_radius(r, a, c, prng) : Float64
      d = adjacent_dead_angles(a, c.sectors, SECTOR_NUM)
      unless d.empty?
        return average_radius(d) + prng.rand(LAYER_DIST * 2)
      end
      r * growth_rate(a, c) + LAYER_DIST * prng.rand(LAYER_MAX)
    end

    def average_radius(d) : Float64
      d.sum(0) / d.size
    end

    def growth_rate(a, c) : Float64
      n = (a * SECTOR_RES).round.to_i % 360
      Blend.step(1, c.growth[n], Blend.pos(c.layers.size, 20))
    end

    def sector_angle(p1, p2) : Int32
      d = Geo.rad_to_deg(Geo.angle_from_points(p1, p2)) + 180
      (d / SECTOR_RES).to_i
    end

    def adjacent_dead_angles(a, s, n) : Array(Float64)
      o = (10 + n / 360).round.to_i
      (-o..o).compact_map { |i| s[(n + a + i).to_i % n]? }
    end
  end

  module Blend
    extend self

    def step(f, t, p) : Float64
      return f.to_f if p <= 0
      return t.to_f if p >= 1
      f + (t - f) * p
    end

    def pos(c, t) : Float64
      (1.0 / t) * c
    end

    def linear(s, e, n) : Array(Float64)
      (0..n).map { |i| (s + ((e - s) / n) * i).round(2) }
    end

    def key_points(ks, n) : Array(Float64)
      b = (0..(ks.size - 1)).reduce([] of Float64) do |m, i|
        if k = ks[i.succ]?
          (m += linear(ks[i][1], k[1], k[0] - ks[i][0])[..-2])
        else
          m
        end
      end
      t = (n - ks.last[0]).to_i
      w = linear(ks.last[1], ks[0][1], t + ks[0][0])[..-2]
      w[t..] + b + w[..(t - 1)]
    end
  end

  module Deactivation
    extend self

    def update(cs) : Void
      predicted_growth(cs).each.with_index do |g, i|
        next unless gs = g
        cs.each.with_index do |c, j|
          next unless (ps = c.layers.last) && i != j
          ps.each { |p| register_death(c, p, gs) }
        end
      end
    end

    def register_death(c, p, ps) : Void
      a = angle(c.cp, p) % SECTOR_NUM
      if c.sectors[a].nil? && Geo.point_in_polygon?(p, ps)
        c.sectors[a] = Geo.point_distance(c.cp, p)
      end
    end

    def angle(p1, p2) : Int32
      d = Geo.rad_to_deg(Geo.angle_from_points(p1, p2)) + 180
      (d / SECTOR_RES).to_i
    end

    def predicted_growth(cs) : Array(Array(Point)?)
      cs.map do |c|
        if ps = c.layers.last
          resample_polygon(ps).map do |p|
            d = Geo.point_distance(c.cp, p) + PREDICT_DIST
            a = Geo.angle_from_points(c.cp, p)
            Geo.point_on_circle(c.cp, d, a)
          end
        end
      end
    end

    def resample_polygon(ps, f = 3)
      ps.map_with_index { |a, i| a if i % f == 0 }.compact
    end
  end

  module Path
    extend self

    def from_points(ps)
      ps.map_with_index do |p, i|
        i == 0 ? start(p) : bezier(p, i, ps)
      end.join(' ') + stop
    end

    def start(p) : String
      %(M #{p[0]},#{p[1]})
    end

    def stop : String
      %(z)
    end

    def bezier(p, i, a) : String
      s = a[i - 1]
      cs_x, cs_y = control_point(s, a[i - 2], p, false)
      ce_x, ce_y = control_point(p, s, a[(i + 1) % a.size])
      %(C #{cs_x},#{cs_y} #{ce_x},#{ce_y} #{p[0]},#{p[1]})
    end

    def control_point(c, p, n, r = true) : Point
      l, a = line_prop(p || c, n || c)
      a += Math::PI if r
      {(c[0] + Math.cos(a) * l * LAYER_SMOOTH).round(1),
       (c[1] + Math.sin(a) * l * LAYER_SMOOTH).round(1)}
    end

    def line_prop(p1, p2) : Tuple(Float64, Float64)
      lx, ly = p2[0] - p1[0], p2[1] - p1[1]
      {Math.hypot(lx, ly), Math.atan2(ly, lx)}
    end
  end

  module Geo
    extend self

    def angle_from_points(p1, p2) : Float64
      Math.atan2(p2[1] - p1[1], p2[0] - p1[0])
    end

    def r_to_length(r) : Float64
      r * 2 * Math::PI
    end

    def deg_to_rad(deg) : Float64
      deg * Math::PI / 180
    end

    def rad_to_deg(rad) : Float64
      rad * 180 / Math::PI
    end

    def point_distance(p1, p2) : Float64
      Math.hypot(p1[0] - p2[0], p1[1] - p2[1])
    end

    def point_on_circle(cp, r, a) : Point
      {(cp[0] + r * Math.cos(a)).round(2),
       (cp[1] + r * Math.sin(a)).round(2)}
    end

    def random_point_on_circle(prng) : Point
      r, rad = SIZE_VB / 2, prng.rand(Math::TAU)
      {(r + Math.cos(rad) * r * prng.rand).round(2),
       (r + Math.sin(rad) * r * prng.rand).round(2)}
    end

    def point_in_polygon?(p, ps) : Bool
      inside, prev = false, ps.size - 1
      ps.each.with_index do |pt, i|
        inside = !inside if point_intersect?(p, pt, ps[prev])
        prev = i
      end
      inside
    end

    def point_intersect?(p, p1, p2) : Bool
      ((p1[1] > p[1]) != (p2[1] > p[1])) &&
        (p[0] < (p2[0] - p1[0]) *
                (p[1] - p1[1]) / (p2[1] - p1[1]) + p1[0])
    end
  end

  module Svg
    extend self

    def build(color, cores, prng, layer_flow)
      XML.build_fragment(indent: %(  )) do |svg|
        Layer.build(cores, prng, layer_flow)
        d, v, h = SIZE_DOC, SIZE_VB, SIZE_VB / 2

        svg.element(%(svg),
          xmlns: %(http://www.w3.org/2000/svg),
          version: %(1.1), stroke: COLORS[color], fill: FILL,
          width: d, height: d, viewBox: %(0 0 #{v} #{v})) do
          svg.element(%(defs)) do
            svg.element(%(clipPath), id: %(clip)) do
              svg.element(%(circle), r: h, cx: h, cy: h)
            end
          end
          svg.element(%(g), %(clip-path): %(url(#clip))) do
            svg.element(%(rect), width: v, height: v)
            cores.each do |core|
              o = 1 / core.layers.size
              core.layers.reverse.each.with_index do |points, i|
                swmin, swmax = STROKE_WIDTH
                somin, somax = STROKE_OPACITY
                sw = (swmin + prng.rand(swmax - swmin)).round(2)
                so = (somin + prng.rand(somax = somin)).round(2)
                fo = Math.max(0.5 - i * o, 0)
                svg.element(%(path),
                  d: Path.from_points(points),
                  %(fill-opacity): fo,
                  %(stroke-width): sw, %(stroke-opacity): so)
              end
            end
          end
        end
      end
    end
  end

  struct FloatFromInt
    def self.from_json(pull : JSON::PullParser)
      pull.read_int.to_f
    end

    def self.to_json(value : Float64, json : JSON::Builder)
      json.scalar(value.to_i)
    end
  end

  struct PointFromArray
    def self.from_json(pull : JSON::PullParser)
      pull.read_begin_array
      x, y = pull.read_int, pull.read_int
      pull.read_end_array
      {x.to_f, y.to_f}
    end

    def self.to_json(value : Point, json : JSON::Builder)
      json.start_array
      json.scalar(value[0].to_i)
      json.scalar(value[1].to_i)
      json.end_array
    end
  end
end

# Uncomment lines 453-465 to generate a Dendro. The output will
# be an SVG-formatted string. Copy and paste it into a new file,
# and call is for example 'dendro.svg'.
#
# Replace the values below with the values of your Dendro. They
# can be found in the metadata of your NFT.
#
# number = 1             # integer value (1-3000)
# color_id = 0           # integer value (0-5)
# previous_cores = %([]) # JSON string (array of cores)
# add_core = false       # boolean value (true/false)

# dendro = Dendro.new(
#   seed: number,
#   color: color_id,
#   previous_cores: previous_cores,
#   add_core: add_core
# )

# puts dendro.to_svg
