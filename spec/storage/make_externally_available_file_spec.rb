# frozen_string_literal: true

require 'spec_helper'
require 'teak_util/storage/make_externally_available_file'

RSpec.describe TeakUtil::Storage::MakeExternallyAvailableFile do
  let(:storage) { instance_double(TeakUtil::Storage::S3) }
  let(:client) { Aws::S3::Client.new(stub_responses: true) }
  let(:value) { 'testing' }
  let(:key) { 'test.txt' }
  let(:bucket_name) { 'test' }
  let(:prefix) { '/test' }
  let(:compress) { false }
  let(:url) { "https://example.com/#{SecureRandom.hex}" }
  let(:opts) do
    {
      bucket_name: bucket_name,
      prefix: prefix,
      key: key,
      value: value,
      compress: compress
    }
  end

  subject(:result) { @result }

  def perform
    described_class.call(opts)
  end

  before do
    Timecop.freeze
    allow(Aws::S3::Client).to receive(:new).and_return(client)
    allow(TeakUtil::Storage::S3).to receive(:new).and_return(storage)
    allow(storage).to receive(:put) { |key, value, opts={}| @value = value; "#{prefix}/#{key}" }
    allow(storage).to receive(:public_url).and_return(url)
    @result = perform
  end

  after { Timecop.return }

  it 'uses S3 storage' do
    datestr = Time.now.utc.strftime("%Y/%m/%d/")
    expect(TeakUtil::Storage::S3).to have_received(:new).with(
      bucket_name,
      prefix: "#{prefix}#{datestr}"
    )
  end

  it 'stores the file contents' do
    expect(storage).to have_received(:put).with(
      key, value, {
        content_type: 'text/plain',
        content_disposition: "attachment; filename=\"#{key}\""
      }
    )
  end

  it 'provides the public url' do
    expect(result.public_url).to eq url
  end

  it 'provides the fully qualifed key' do
    expect(result.full_path).to eq "#{prefix}/#{key}"
  end

  context 'with compress' do
    let(:compress) { true }

    it 'appends .zip to the stored file' do
      expect(storage).to have_received(:put).with(
        "#{key}.zip", anything, {
          content_type: 'application/zip',
          content_disposition: "attachment; filename=\"#{key}.zip\""
        }
      )
    end

    it 'compresses the file' do
      entries = {}
      Zip::File.open_buffer(StringIO.new(@value)) do |zip_file|
        zip_file.each do |entry|
          entries[entry.name] = entry.get_input_stream.read
        end
      end

      expect(entries).to eq(key => value)
    end
  end

  context 'without a bucket or storage' do
    let(:bucket_name) { nil }

    it 'errors' do
      expect(result.errors[:storage]).to include(include("must not be nil"))
    end
  end

  context 'with multiple values' do
    let(:key) { 'test' }

    let(:value) do
      {
        'file1.txt' => 'testing',
        'file2.txt' => 'more testing'
      }
    end

    context 'without compression' do
      let(:compress) { false }

      it 'errors' do
        expect(result.errors[:compress]).to include(include('must be true when storing multiple files'))
      end
    end

    context 'with compression' do
      let(:compress) { true }

      it 'appends .zip to the stored file' do
        expect(storage).to have_received(:put).with(
          "#{key}.zip", anything, {
            content_type: 'application/zip',
            content_disposition: "attachment; filename=\"#{key}.zip\""
          }
        )
      end

      it 'zips all values into the stored file' do
        entries = {}
        Zip::File.open_buffer(StringIO.new(@value)) do |zip_file|
          zip_file.each do |entry|
            entries[entry.name] = entry.get_input_stream.read
          end
        end

        expect(entries).to eq value
      end
    end
  end
end
