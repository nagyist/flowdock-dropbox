require 'spec_helper'

ENV["FLOW_TOKENS"] = "deadbeefdeadbeef, 3ee7818aab66ee16f5d30cfd96e0100c "
ENV["SOURCE"] = "dropbox"
ENV["FROM_ADDRESS"] = "foo@example.com"
ENV["FROM_NAME"] = "Dropbox"

ENV["APP_KEY"] = 'invalid'
ENV["APP_SECRET"] = 'invalid'

ENV["USER_TOKEN"] = 'invalid'
ENV["USER_SECRET"] = 'invalid'

ENV["DROPBOX_PATH"] = "/"

describe DropboxPoller do
  describe "when running for the first time" do
    it "initializes Dropbox session and client" do
      DropboxSession.should_receive(:new).and_return(FakeDropboxSession.new)
      DropboxClient.should_receive(:new).and_return(FakeDropboxClient.new)
      @poller = DropboxPoller.new
      @poller.run!.should eq(true)
    end
  end

  describe "when listening for deltas" do
    before :all do
      @poller = DropboxPoller.new
      @poller.stub(:polling_interval).and_return(5)
      @poller.session = FakeDropboxSession.new
      @poller.client = FakeDropboxClient.new
      @poller.should_not_receive(:init_session)
    end

    it "parses initial state (delta1 & delta2)" do
      should_not_send_notifications
      @poller.run!
      @poller.folder_state.should_not be_empty
      @poller.folder_state["/test/index.html"].should_not be_nil
    end

    it "parses adding a folder with files and aggregates it into one notification (delta3)" do
      should_send_notification({:tags => ["dropbox"], :subject => "Folder testing2 added",
        :content => "Folder <a href=\"https://www.dropbox.com/home/testing2\">testing2</a> was added.",
        :link => "https://www.dropbox.com/home/testing2"})
      @poller.run!
    end

    it "parses adding a file (delta4)" do
      should_send_notification({:tags => ["dropbox"], :subject => "File influx_bug.png added",
        :content => "File <a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">influx_bug.png</a> was added to <a href=\"https://www.dropbox.com/home/\">Home</a>.",
        :link => "https://www.dropbox.com/home/"})
      @poller.run!
    end

    it "parses deleting a file (delta5)" do
      should_send_notification({:tags => ["dropbox"], :subject => "File influx_bug.png deleted",
        :content => "File influx_bug.png was deleted from <a href=\"https://www.dropbox.com/home/\">Home</a>.",
        :link => "https://www.dropbox.com/home/"})
      @poller.run!
    end

    it "parses deleting folder with files and aggregates it into one notification (delta6)" do
      should_send_notification({:tags => ["dropbox"], :subject => "Folder testing2 deleted",
        :content => "Folder testing2 was deleted.",
        :link => nil})
      @poller.run!
    end

    it "parses updating a file (delta7)" do
      should_send_notification({:tags => ["dropbox"], :subject => "File index.html updated",
        :content => "File <a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">index.html</a> was updated in <a href=\"https://www.dropbox.com/home/test\">/test</a>.",
        :link => "https://www.dropbox.com/home/test"})
      @poller.run!
    end

    it "parses adding a file and a folder with one file (delta8)" do
      should_send_notification({:tags => ["dropbox"], :subject => "File another_bug.png added",
        :content => "File <a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">another_bug.png</a> was added to <a href=\"https://www.dropbox.com/home/\">Home</a>.",
        :link => "https://www.dropbox.com/home/"})
      should_send_notification({:tags => ["dropbox"], :subject => "Folder test2 added",
        :content => "Folder <a href=\"https://www.dropbox.com/home/test2\">test2</a> was added.",
        :link => "https://www.dropbox.com/home/test2"})
      @poller.run!
    end

    it "parses adding a file and a folder with one file in chunked deltas (delta9 & delta10)" do
      should_send_notification({:tags => ["dropbox"], :subject => "File influx_bug.png added",
        :content => "File <a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">influx_bug.png</a> was added to <a href=\"https://www.dropbox.com/home/\">Home</a>.",
        :link => "https://www.dropbox.com/home/"})
      should_send_notification({:tags => ["dropbox"], :subject => "Folder testing2 added",
        :content => "Folder <a href=\"https://www.dropbox.com/home/testing2\">testing2</a> was added.",
        :link => "https://www.dropbox.com/home/testing2"})
      @poller.run!
    end

    it "parses adding two files and deleting one file inside the same folder into one aggregated notification (delta11)" do
      should_send_notification({:tags => ["dropbox"], :subject => "Activity in testing2: 2 files added, 1 file deleted",
        :content =>
          "<strong>Added:</strong><ul>" +
          "<li><a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">influx_bug.png</a></li>" +
          "<li><a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">another_influx_bug.png</a></li></ul>" +
          "<strong>Deleted:</strong><ul>" +
          "<li>tide.png</li></ul>",
        :link => "https://www.dropbox.com/home/testing2"})
      @poller.run!
    end

    it "parses adding activity in folder (1 add, 1 update, 1 delete) + adding one other file into an aggregated notification for the folder and a separate file notification (delta12)" do
      should_send_notification({:tags => ["dropbox"], :subject => "Activity in testing2: 1 file added, 1 file updated, 1 file deleted",
        :content =>
          "<strong>Added:</strong><ul>" +
          "<li><a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">yet_another_influx_bug.png</a></li></ul>" +
          "<strong>Updated:</strong><ul>" +
          "<li><a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">another_influx_bug.png</a></li></ul>" +
          "<strong>Deleted:</strong><ul>" +
          "<li>influx_bug.png</li></ul>",
        :link => "https://www.dropbox.com/home/testing2"})
      should_send_notification({:tags => ["dropbox"], :subject => "File other_bug.png added",
        :content => "File <a href=\"https://www.dropbox.com/s/q6p2bn9td2wjwfb\">other_bug.png</a> was added to <a href=\"https://www.dropbox.com/home/\">Home</a>.",
        :link => "https://www.dropbox.com/home/"})
      @poller.run!
    end
  end

  describe "with DROPBOX_PATH option" do
    before :all do
      @poller = DropboxPoller.new
      @poller.stub(:polling_interval).and_return(5)
      @poller.session = FakeDropboxSession.new
      @poller.client = FakeDropboxClient.new
      @poller.follow_path = "/photos"
      @poller.should_not_receive(:init_session)
    end

    it "parses initial state (delta1 & delta2)" do
      should_not_send_notifications
      @poller.run!
      @poller.folder_state.should_not be_empty
      @poller.folder_state["/photos/sample album"].should_not be_nil
      @poller.folder_state["/test/index.html"].should be_nil
    end

    it "ignores folder outside the defined path (delta3)" do
      should_not_send_notifications
      @poller.run!
    end
  end

  def should_send_notification(params)
    @poller.flows.each { |flow| flow.should_receive(:push_to_team_inbox).with(params).once }
  end

  def should_not_send_notifications
    @poller.flows.each { |flow| flow.should_not_receive(:push_to_team_inbox) }
  end
end