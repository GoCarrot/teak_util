# frozen_string_literal: true

require 'digest'
require 'English'
require 'set'

module TeakUtil
  # Derives a worktree-scoped test database name from a checkout's directory basename,
  # and purges databases left behind by worktrees that no longer exist. Deliberately
  # standalone-requirable (no dependency on the rest of teak_util) since it's typically
  # evaluated from an ERB database config at app boot.
  module TestDatabaseName
    MAX_IDENTIFIER_LENGTH = 64 # MySQL's identifier limit
    HASH_LENGTH = 8

    DEFAULT_WORKTREE_LISTER = lambda do
      output = `git worktree list --porcelain`
      raise '`git worktree list --porcelain` failed. Are you in a git repository?' unless $CHILD_STATUS.success?

      output
    end

    module_function

    # @param basename [String] the checkout's directory basename
    # @param base [String] the database name used by the main (non-worktree) checkout,
    #   e.g. 'taro_posts_test'
    # @param main_worktree [String] the directory name of the main checkout, e.g. 'taro' —
    #   compared case-insensitively so `main_worktree` gets `base` back unmodified
    def for_worktree(basename, base:, main_worktree:)
      downcased = basename.downcase
      return base if downcased == main_worktree.downcase

      sanitized = downcased.gsub(/[^a-z0-9]+/, '_')
      budget = MAX_IDENTIFIER_LENGTH - base.length - 1 # 1 for the joining underscore
      raise ArgumentError, "base #{base.inspect} leaves no room for a worktree suffix" if budget <= 0

      if sanitized.length > budget
        hash = Digest::SHA256.hexdigest(sanitized)[0, HASH_LENGTH]
        truncated_length = budget - hash.length - 1 # 1 for the underscore before the hash
        raise ArgumentError, "base #{base.inspect} leaves no room for a worktree suffix" if truncated_length <= 0

        sanitized = "#{sanitized[0, truncated_length]}_#{hash}"
      end

      "#{base}_#{sanitized}"
    end

    # Lists and drops test databases for worktrees that no longer exist.
    #
    # @param connection [#fetch, #run] a Sequel-connection-shaped object
    # @param base [String] as for #for_worktree
    # @param main_worktree [String] as for #for_worktree
    # @param input [#gets] prompt source
    # @param output [#puts, #print] prompt/progress sink
    # @param worktree_lister [#call] returns `git worktree list --porcelain` output;
    #   must raise on failure — the default does. A custom lister inherits that
    #   contract; a lister that swallows a failed listing will read as "no active
    #   worktrees" and offer to drop every database this basename owns.
    def purge(connection:, base:, main_worktree:, input: $stdin, output: $stdout,
              worktree_lister: DEFAULT_WORKTREE_LISTER)
      escaped_base = base.gsub(/[\\_%]/) { |match| "\\#{match}" }
      rows = connection.fetch("SHOW DATABASES LIKE '#{escaped_base}\\_%'").map { |row| row.values.first }

      active = worktree_lister.call.lines
                 .select { |line| line.start_with?('worktree ') }
                 .map { |line| File.basename(line.sub('worktree ', '').strip) }
                 .to_set { |basename| for_worktree(basename, base: base, main_worktree: main_worktree) }

      defunct = rows - active.to_a

      if defunct.empty?
        output.puts 'No defunct worktree test databases found.'
        return
      end

      output.puts "Found #{defunct.size} defunct worktree test database(s):"
      defunct.each { |db| output.puts "  - #{db}" }

      output.print "\nDrop all of them? [y/N] "
      answer = input.gets&.strip
      unless answer&.match?(/\Ay(es)?\z/i)
        output.puts 'Aborted.'
        return
      end

      defunct.each do |db|
        output.puts "Dropping #{db}..."
        connection.run("DROP DATABASE `#{db}`")
      end
      output.puts 'Done.'
    end
  end
end
