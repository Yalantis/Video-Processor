require "spec_helper"

require Rails.root.join('spec', 'controllers', 'api', 'v1', 'shared_examples', 'unauthorized_user_error.rb')
require Rails.root.join('spec', 'controllers', 'api', 'v1', 'shared_examples', 'data_not_found_error.rb')

describe Api::V1::VideoProcessingInfosController, type: :api do
  describe "POST create" do
    context 'when user is authenticated' do
      before do
        create_authenticated_user
      end

      context "with valid params" do
        before do
          @params = {
            "video_processing_info" => {
              "trim_start" => 2,
              "trim_end" => 12,
              "source_video" => fixture_file_upload("#{::Rails.root}/spec/fixtures/videos/test_video.mov", 'video/quicktime')
            }
          }
        end

        it "should create video_processing_info and return it's json data" do
          expect { post "/api/v1/video_processing_infos.json", @params, @auth_params }.to change { @user.video_processing_infos.count }.by(1)

          expect(last_response.status).to eql http_status_for(:created)

          expect(json["trim_start"]).to eql @params["video_processing_info"]["trim_start"]
          expect(json["trim_end"]).to eql @params["video_processing_info"]["trim_end"]

          expect(json["state"]).to eql "scheduled"

          video_processing_info = @user.video_processing_infos.last

          expect(json["source_video"]["url"]).to eql video_processing_info.source_video.url

          expect(json).to match(video_processing_info_hash(video_processing_info))
        end
      end

      context "with invalid params" do
        before do
          @params = {
            "video_processing_info" => {
              "trim_start" => 5
            }
          }
        end

        it "should not create video_processing_info and return error" do
          expect { post "/api/v1/video_processing_infos.json", @params, @auth_params }.to_not change { @user.video_processing_infos.count }

          expect(last_response.status).to eql http_status_for(:unprocessable_entity)

          expected_error_hash = {
            "error" => "Trim end can't be blank",
            "details" => {
              "trim_end" => ["can't be blank", "is not a number"],
              "source_video"=>["can't be blank"]
            }
          }

          expect(json).to match(expected_error_hash)
        end
      end
    end

    context 'when user is not authenticated' do
      before do
        @params = {
          "video_processing_info" => {
            "trim_start" => 2,
            "trim_end" => 12,
            "source_video" => fixture_file_upload("#{::Rails.root}/spec/fixtures/videos/test_video.mov", 'video/quicktime')
          }
        }
      end

      it "should not create video_processing_info" do
        expect { post "/api/v1/video_processing_infos.json", @params, {} }.to_not change { VideoProcessingInfo.count }
      end

      it_behaves_like "return error for unauthorized user", :post, '/api/v1/video_processing_infos.json', @params
    end
  end

  describe "GET index" do
    context 'when user is not authenticated' do
      it_behaves_like "return error for unauthorized user", :post, '/api/v1/video_processing_infos.json'
    end

    context 'when user is authenticated' do
      before do
        create_authenticated_user
      end

      context "with valid params" do
        before do
          @video_processing_infos = 3.times.map do |i|
            travel_to (Time.zone.now - i.hour) do
              create(:video_processing_info, user: @user)
            end
          end
        end

        it "should return list video_processing_infos in descending creation order" do
          get "/api/v1/video_processing_infos.json", {}, @auth_params

          expect(last_response.status).to eql http_status_for(:ok)

          expect(json).to be_kind_of(Array)
          expect(json.size).to eql(3)

          expect(json[2]).to match(video_processing_info_hash(@video_processing_infos[2]))
          expect(json[1]).to match(video_processing_info_hash(@video_processing_infos[1]))
          expect(json[0]).to match(video_processing_info_hash(@video_processing_infos[0]))
        end

        context 'when pagination params are provided' do
          before do
            @params = {
              "per_page" => 1,
              "page" => 2
            }
          end

          it "should return specified page only" do
            get "/api/v1/video_processing_infos.json", @params, @auth_params

            expect(last_response.status).to eql http_status_for(:ok)

            expect(json).to be_kind_of(Array)
            expect(json.size).to eql(1)
            expect(json.first).to match(video_processing_info_hash(@video_processing_infos[1]))
          end
        end
      end
    end
  end

  describe "PATCH restart" do
    context 'when user is not authenticated' do
      it_behaves_like "return error for unauthorized user", :patch, "/api/v1/video_processing_infos/#{FactoryGirl.create(:video_processing_info).id}/restart.json"
    end

    context 'when user is authenticated' do
      before do
        create_authenticated_user
      end

      context "when video_processing_info is not exist" do
        it_behaves_like "return error if data is not found", :patch, "/api/v1/video_processing_infos/not_exitsting_id_#{rand(100)}/restart.json"
      end

      context "when video_processing_info is not belong to current user" do
        it_behaves_like "return error if data is not found", :patch, "/api/v1/video_processing_infos/#{FactoryGirl.create(:video_processing_info, state: "failed").id}/restart.json"
      end

      context 'when video_processing_info can not be restarted' do
        before do
          @video_processing_info = create(:video_processing_info, state: "done", user: @user)
        end

        it "shoud return error" do
          patch "/api/v1/video_processing_infos/#{@video_processing_info.id}/restart.json", @params, @auth_params

          expect(last_response.status).to eql http_status_for(:unprocessable_entity)

          expected_error_hash = {
            "error" => I18n.t("api.errors..data.invalid_transition", state_attr_name: "state", current_state_name: "done", event_name: "schedule"),
            "details" => {}
          }

          expect(json).to match(expected_error_hash)
        end
      end

      context 'when video_processing_info can be restarted' do
        before do
          @video_processing_info = create(:video_processing_info, state: "failed", user: @user)
        end

        it "should successfully switch state from failed to scheduled and return this video_processing_info json" do
          expect { patch "/api/v1/video_processing_infos/#{@video_processing_info.id}/restart.json", @params, @auth_params }.to change { @video_processing_info.reload.state }.from("failed").to("scheduled")

          expect(last_response.status).to eql http_status_for(:accepted)
          expect(json).to match(video_processing_info_hash(@video_processing_info.reload))
        end
      end
    end
  end

  private
    def video_processing_info_hash(video_processing_info)
      {
        "id" => video_processing_info.id.to_s,
        "trim_start" => video_processing_info.trim_start,
        "trim_end" => video_processing_info.trim_end,
        "source_video" => {
          "url" => video_processing_info.source_video.url,
          "duration" => video_processing_info.source_video_duration
        },
        "result_video" => {
          "url" => video_processing_info.result_video? ? video_processing_info.result_video.url : nil,
          "duration" => video_processing_info.result_video_duration
        },
        "started_at" => video_processing_info.started_at? ? video_processing_info.started_at.to_i : nil ,
        "completed_at" => video_processing_info.completed_at? ? video_processing_info.completed_at.to_i : nil,
        "failed_at" => video_processing_info.failed_at? ? video_processing_info.to_i : nil,
        "state" => video_processing_info.state
      }
    end

end
