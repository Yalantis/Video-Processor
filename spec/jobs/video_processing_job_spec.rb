require 'rails_helper'

RSpec.describe VideoProcessingJob, type: :job do
  let(:video_processing_info) { build_stubbed(:video_processing_info) }
  subject(:job) { described_class.perform_later(video_processing_info) }

  it 'queues the job' do
    expect { job }.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size).by(1)
  end

  it 'is in video_processing queue' do
    expect(described_class.new.queue_name).to eq('video_processing')
  end

  it 'executes perform' do
    expect(VideoProcessingInfo).to receive(:find).with(video_processing_info.id.to_s).and_return(video_processing_info)
    video_trimmer = double(:video_trimmer)
    expect(VideoTrimmer).to receive(:new).with(video_processing_info).and_return(video_trimmer)
    expect(video_trimmer).to receive(:perform!)
    perform_enqueued_jobs { job }
  end
end
