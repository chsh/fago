require 'digest/md5'

class SequenceBuilder
  def initialize(in_dir, out_dir)
    @in_dir = in_dir
    @out_dir = out_dir
    @now = Time.zone.now
  end

  attr_reader :in_dir, :out_dir, :now, :one_seq, :ext, :seq_span, :skip_first, :skip_last

  SEQ_EXTS = %w(jpg jpeg png dng ori orf)
  SINGLE_EXTS = %w(mov mp4 lrv)

  def export(one_seq: false, dry_run: false, ext: nil, seq_span: nil, skip_first: false, skip_last: false)
    @one_seq = one_seq ? true : false
    dry_run = dry_run ? true : false
    @skip_first = skip_first ? true : false
    @skip_last = skip_last ? true : false
    @ext = ext.present? ? [ext].flatten.map(&:downcase) : SEQ_EXTS+SINGLE_EXTS
    @seq_span = seq_span

    verify_dir(in_dir) || raise("in_dir=#{in_dir} not present.")
    verify_dir(out_dir) || create_dir(out_dir) and "out_dir=#{out_dir} created."

    targets = filter_images(files)
    ext_to_files = files_by_ext(targets)

    log "Start processing."
    clip_seq = 1
    ext_to_files.each do |ext, list|
      log "processing :#{ext}"
      sorted_list = sort_by_time_and_name(list)
      groups = groups_by_span(sorted_list, ext: ext)
      log "groups.size=#{groups.size}"
      groups.each_with_index do |group, index|
        log "#{dry_run ? 'DRY RUN ' : ''}ext:#{ext}, group=#{index}, size=#{group.size}, first=#{group[0].file}"
        process_clip_seq(ext, group, clip_seq) unless dry_run
        clip_seq += 1
      end
    end
    log "finished"
    log "Saved to #{target_dir}"
  end

  def prepare
    export(dry_run: true)
  end

  def dry_run(options = {})
    export(options.merge(dry_run: true))
  end

  private

  def current_seq_span
    seq_span || 5.0
  end
  def files
    @files ||= files_with_stat(glob_files(in_dir))
  end

  def sort_by_time_and_name(list)
    list.sort { |a,b|
      [a.last_modified_at, a.file] <=> [b.last_modified_at, b.file]
    }
  end

  def verify_dir(dir)
    Dir.exist?(dir)
  end

  def glob_files(dir)
    log "Grobbing files from=#{dir}"
    files = Dir.glob("#{dir}/**/*")
    log "Globbed: num=#{files.size}"
    files
  end

  def filter_images(list)
    log "Filtering images..."
    list.select { |hash| File.extname(hash.file).gsub(/\A\./, '').downcase.in?(ext) }
  end

  def files_by_ext(list)
    log "Ext grouping..."
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
    log "Checking stats..."
    total = files.size
    files.map.with_index do |file, index|
      log "#{Time.zone.now}: #{index}/#{total}", index > 0 && index % 500 == 0
      StatHash.from_file(file)
    end
  end

  def groups_by_span(list, ext:)
    if ext.in? SEQ_EXTS
      if one_seq
        groups_by_span_for_one(list)
      else
        groups_by_span_for_seq(list)
      end
    else
      groups_by_span_for_single(list)
    end
  end

  def groups_by_span_for_one(list)
    groups = []
    groups[0] = list
    groups
  end

  def groups_by_span_for_seq(list)
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

  def groups_by_span_for_single(list)
    list.map { |hash| [hash] }
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
      puts "list.size=#{list.size}, index=#{index}"
      prev_data = list[index-1]
      cur_data = list[index]
      next_data = list[index+1]
      if next_data.nil?
        :new
      else
        span1 = cur_data.last_modified_at - prev_data.last_modified_at
        span2 = next_data.last_modified_at - cur_data.last_modified_at
        if (span2 - span1).abs <= current_seq_span
          :cont
        else
          :new
        end
      end
    elsif prev_marker == :cont
      prev_prev_data = list[index-2]
      prev_data = list[index-1]
      cur_data = list[index]
      span1 = prev_data.last_modified_at - prev_prev_data.last_modified_at
      span2 = cur_data.last_modified_at - prev_data.last_modified_at
      if (span2 - span1).abs <= current_seq_span
        :cont
      else
        :new
      end
    else
      raise "Unexpected state. index=#{index}, prev_marker=#{prev_marker}"
    end
  end

  def target_dir
    @target_dir ||= begin
      now_s = now.strftime('%Y%m%d-')
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
    FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
    if ext.in?(SEQ_EXTS) && list.size > 1
      to_dir = "#{target_dir}/c#{clip_seq}-seq-#{list.size}"
      FileUtils.mkdir(to_dir) unless Dir.exist?(to_dir)
      list_size = list.size
      list.each_with_index do |hash, index|
        fn = sprintf("seq%06d.#{ext}", index + 1)
        if execute_process_clip_seq?(index, list_size)
          FileUtils.cp(hash.file, "#{to_dir}/#{fn}")
        end
      end
    else # SINGLE_EXTS or SEQ_EXTS && size == 1
      to_file = "#{target_dir}/c#{clip_seq}.#{ext}"
      FileUtils.cp(list[0].file, to_file)
    end
    # cmd = "ffmpeg -r 60 -f image2 -i #{to_dir}/seq%06d.#{ext} -vcodec prores -qp 0 #{target_dir}/c#{clip_seq}.mov"
    # log cmd
    # `#{cmd}`
  end

  def execute_process_clip_seq?(index, list_size)
    return false if index == 0 && skip_first
    return false if index == list_size-1 && skip_last
    true
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
