module Util
  extend self

  def svg_file_name(number : Int32) : String
    "playground/dendro-#{number}-#{Time.utc.to_s("%Y%m%d%H%I%S")}.svg"
  end

  def js_to_json(js : String) : String
    js.gsub(/([a-z_]+):/, %("\\1":))
  end
end
