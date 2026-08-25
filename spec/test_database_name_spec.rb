# frozen_string_literal: true

require 'teak_util/test_database_name'
require 'tmpdir'

RSpec.describe TeakUtil::TestDatabaseName do
  it 'loads without pulling in the rest of the gem' do
    script = "require 'teak_util/test_database_name'; exit(defined?(Aws) ? 1 : 0)"
    expect(system(RbConfig.ruby, '-Ilib', '-e', script)).to be true
  end

  describe '.for_worktree' do
    it 'returns base unmodified for the main worktree, case-insensitively', :aggregate_failures do
      expect(described_class.for_worktree('taro', base: 'taro_posts_test', main_worktree: 'taro'))
        .to eq('taro_posts_test')
      expect(described_class.for_worktree('Taro', base: 'taro_posts_test', main_worktree: 'taro'))
        .to eq('taro_posts_test')
    end

    it 'downcases and squashes non-alphanumeric runs to a single underscore' do
      expect(described_class.for_worktree('taro-Feature.C 1532', base: 'taro_posts_test', main_worktree: 'taro'))
        .to eq('taro_posts_test_taro_feature_c_1532')
    end

    it 'truncates an over-length basename to stay within the MySQL identifier limit', :aggregate_failures do
      basename = "taro-feature-#{'x' * 80}"
      result = described_class.for_worktree(basename, base: 'taro_posts_test', main_worktree: 'taro')

      expect(result.length).to be <= 64
      expect(result).to start_with('taro_posts_test_taro_feature_')
    end

    it 'disambiguates two long basenames that share a common prefix' do
      shared_prefix = "taro-feature-c-1080-#{'x' * 60}"
      first = described_class.for_worktree("#{shared_prefix}-alpha", base: 'taro_posts_test', main_worktree: 'taro')
      second = described_class.for_worktree("#{shared_prefix}-beta", base: 'taro_posts_test', main_worktree: 'taro')

      expect(first).not_to eq(second)
    end

    it 'raises when base leaves no room for a worktree suffix' do
      expect do
        described_class.for_worktree('feature-branch', base: 'x' * 64, main_worktree: 'taro')
      end.to raise_error(ArgumentError)
    end

    it 'raises when base leaves no room for the truncation hash' do
      expect do
        described_class.for_worktree('x' * 80, base: 'x' * 55, main_worktree: 'taro')
      end.to raise_error(ArgumentError)
    end

    it 'matches taro and lacewood\'s shipped output for the same inputs', :aggregate_failures do
      expect(described_class.for_worktree('taro-Feature-C-1532-WorktreeTestdb',
                                            base: 'taro_posts_test', main_worktree: 'taro'))
        .to eq('taro_posts_test_taro_feature_c_1532_worktreetestdb')
      expect(described_class.for_worktree('lacewood-Feature-C-1532-WorktreeTestdb',
                                            base: 'lacewood_forwards_test', main_worktree: 'lacewood'))
        .to eq('lacewood_forwards_test_lacewood_feature_c_1532_worktreetestdb')
    end
  end

  describe 'DEFAULT_WORKTREE_LISTER' do
    it 'lists the current checkout\'s worktrees' do
      expect(described_class::DEFAULT_WORKTREE_LISTER.call).to include('worktree ')
    end

    it 'raises when `git worktree list` fails' do
      Dir.chdir(Dir.tmpdir) do
        expect { described_class::DEFAULT_WORKTREE_LISTER.call }.to raise_error(/git worktree list/)
      end
    end
  end

  describe '.purge' do
    let(:connection) { double('connection') }
    let(:input) { StringIO.new }
    let(:output) { StringIO.new }
    let(:worktree_lister) { -> { "worktree /path/to/taro\nworktree /path/to/taro-active\n" } }

    def run_purge(existing_dbs)
      allow(connection).to receive(:fetch)
        .with("SHOW DATABASES LIKE 'taro\\_posts\\_test\\_%'")
        .and_return(existing_dbs.map { |name| { Database: name } })

      described_class.purge(connection: connection, base: 'taro_posts_test', main_worktree: 'taro',
                             input: input, output: output, worktree_lister: worktree_lister)
    end

    it 'reports when nothing is defunct' do
      run_purge(['taro_posts_test_taro_active'])

      expect(output.string).to include('No defunct worktree test databases found.')
    end

    it 'drops defunct databases on confirmation' do
      input.string = "y\n"
      expect(connection).to receive(:run).with('DROP DATABASE `taro_posts_test_taro_stale`')

      run_purge(%w[taro_posts_test_taro_active taro_posts_test_taro_stale])

      expect(output.string).to include('Done.')
    end

    it 'aborts without dropping when declined' do
      input.string = "n\n"
      expect(connection).not_to receive(:run)

      run_purge(%w[taro_posts_test_taro_active taro_posts_test_taro_stale])

      expect(output.string).to include('Aborted.')
    end
  end
end
