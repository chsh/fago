require 'digest/md5'

class SeqenceBuilder
  def initialize(in_dir, out_dir)
    @in_dir = in_dir
    @out_dir = out_dir
    @now = Time.zone.now
  end

  attr_reader :in_dir, :out_dir, :now

  def run
    verify_dir(in_dir) || raise("in_dir=#{in_dir} not present.")
    verify_dir(out_dir) || create_dir(out_dir) and "out_dir=#{out_dir} created."
    log "Grobbing files from=#{in_dir}"
    files = glob_files(in_dir)
    log "Globbed: num=#{files.size}"
    log "Checking stats..."
    files = files_with_stat(files)
    log "Filtering images..."
    files = filter_images(files)
    log "Ext grouping..."
    ext_to_files = files_by_ext(files)
    log "Start processing."
    clip_seq = 1
    ext_to_files.each do |ext, list|
      log "processing :#{ext}"
      sorted_list = list.sort_by(&:last_modified_at)
      groups = groups_by_span(sorted_list)
      log "groups.size=#{groups.size}"
      groups.each_with_index do |group, index|
        log "ext:#{ext}, group=#{index}, size=#{group.size}, first=#{group[0].file}"
        process_clip_seq(ext, group, clip_seq)
        clip_seq += 1
      end
    end
    log "finished"
  end

  private
  def verify_dir(dir)
    Dir.exist?(dir)
  end

  def glob_files(dir)
    Dir.glob("#{dir}/**/*")
  end

  def filter_images(list)
    list.select { |hash| File.extname(hash.file).gsub(/\A\./, '').downcase.in? %w(jpg jpeg png dng ori orf) }
  end

  def files_by_ext(list)
    r = {}
    list.each do |hash|
      ext = File.extname(hash.file).gsub(/\A\./, '').downcase
      r[ext] ||= []
      r[ext] << hash
    end
    r
  end

  def create_dir(dir)
    FileUtils.mkdir_p(dir) || raise("Create dir=#{dir} failed.")
  end

  def files_with_stat(files)
    total = files.size
    files.map.with_index do |file, index|
      log "#{Time.zone.now}: #{index}/#{total}", index > 0 && index % 500 == 0
      StatHash.from_file(file)
    end
  end

  def groups_by_span(list)
    group_index = 0
    groups = []
    marker = nil
    list.each_with_index do |data, index|
      if index == 0
        groups[group_index] ||= []
        groups[group_index] << data
        marker = :new
      else
        marker = detect_span(list, index, marker)
        case marker
        when :new
          group_index += 1
          groups[group_index] = []
        when :cont
        else raise "Unexpected span=#{marker}"
        end
        groups[group_index] << data
      end
    end
    groups
  end

  def log(text, cond = true)
    puts "#{Time.zone.now}: #{text}" if cond
  end

  def detect_span(list, index, prev_marker)
    if list.size < 2
      :new
    elsif index == 0
      :new
    elsif prev_marker == :new
      prev_data = list[index-1]
      cur_data = list[index]
      next_data = list[index+1]
      span1 = cur_data.last_modified_at - prev_data.last_modified_at
      span2 = next_data.last_modified_at - cur_data.last_modified_at
      if (span2 - span1).abs <= 2.0
        :cont
      else
        :new
      end
    elsif prev_marker == :cont
      prev_prev_data = list[index-2]
      prev_data = list[index-1]
      cur_data = list[index]
      span1 = prev_data.last_modified_at - prev_prev_data.last_modified_at
      span2 = cur_data.last_modified_at - prev_data.last_modified_at
      if (span2 - span1).abs <= 2.0
        :cont
      else
        :new
      end
    else
      raise "Unexpected state. index=#{index}, prev_marker=#{prev_marker}"
    end
  end

  def span_within(span_a, span_b)
    avg = (span_a + span_b) / 2.0
    if (span_a - avg).abs <= 1.0 && (span_b - avg).abs <= 1.0
      avg
    else
      nil
    end
  end

  def target_dir
    @target_dir ||= begin
      now_s = now.strftime('%Y-%m-%d--')
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

  def process_clip_seq(ext, list, clip_seq)
    to_dir = "#{target_dir}/c#{clip_seq}-seq"
    FileUtils.mkdir_p(to_dir) unless Dir.exist?(to_dir)
    list.each_with_index do |hash, index|
      fn = sprintf("seq%06d.#{ext}", index + 1)
      FileUtils.cp(hash.file, "#{to_dir}/#{fn}")
    end
    # cmd = "ffmpeg -r 60 -f image2 -i #{to_dir}/seq%06d.#{ext} -vcodec prores -qp 0 #{target_dir}/c#{clip_seq}.mov"
    # log cmd
    # `#{cmd}`
  end

  class StatHash
    concerning :NewInstance do
      included do
        attr_reader :file, :md5, :stat
      end

      class_methods do
        def from_file(file)
          new(file: file,
              md5: Digest::MD5.file(file).to_s,
              stat: File::Stat.new(file))
        end
      end

      def initialize(file:, md5:, stat:)
        @file = file
        @md5 = md5
        @stat = stat
      end

      def last_modified_at
        self.stat.mtime
      end
    end
  end
end
