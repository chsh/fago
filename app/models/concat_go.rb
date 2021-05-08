class ConcatGo
  def initialize(folder)
    @folder = folder.gsub(/\/+$/, '')
  end
  attr_reader :folder

  def run(rm_thms: true, rm_lrvs: true, to: nil)
    if to.present?
      save_dir = target_dir(to)
      FileUtils.mkdir_p save_dir
    else
      save_dir = nil
    end
    make_groups(Dir.glob("#{folder}/*.MP4")).each do |gn, files|
      list_file = "#{folder}/list-#{gn}.txt"
      File.open(list_file, 'w') do |f|
        files.each do |path|
          f.puts "file '#{path}'"
        end
      end
      base_name = "GXA#{gn}.MP4"
      cmd = "ffmpeg -itsscale 0.4166666666666667 -f concat -safe 0 -i #{list_file} -c copy #{folder}/#{base_name}"
      puts cmd
      `#{cmd}`
      File.delete list_file
      if save_dir
        puts "cp #{folder}/#{base_name} to #{save_dir}/#{base_name}"
        FileUtils.cp "#{folder}/#{base_name}", "#{save_dir}/#{base_name}"
      end
    end
  if rm_thms
      Dir.glob("#{folder}/*.THM").map do |file|
        File.delete file
      end
    end
    if rm_lrvs
      Dir.glob("#{folder}/*.LRV").map do |file|
        File.delete file
      end
    end
  end

  private
  def make_groups(files)
    groups = {}
    files.each do |file|
      fn = File.basename(file)
      if fn =~ /GX\d\d(\d+)\./
        gn = $1
        groups[gn] ||= []
        groups[gn] << file
      end
    end
    groups.transform_values { |v| v.sort }
  end

  def target_dir(out_dir)
    now_s = Time.zone.now.strftime('%Y%m%d-')
    dirs = Dir.glob("#{out_dir}/#{now_s}*/")
    if dirs.size == 0
      last_seq = 1
    else
      last_seq = dirs.sort.last.gsub(/\A.*\/#{now_s}/, '').to_i
      last_seq += 1
    end
    "#{out_dir}/#{now_s}#{sprintf('%02d', last_seq)}"
  end
end
