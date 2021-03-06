require 'spec_helper'

describe Guard::RSpec::Runner do
  subject { described_class.new }

  before do
    described_class.any_instance.stub(:failure_exit_code_supported? => true)
  end

  describe '.initialize' do

    describe 'shows warnings for deprecated options' do
      [:color, :drb, [:fail_fast, 'fail-fast'], [:formatter, 'format']].each do |option|
        key, value = option.is_a?(Array) ? option : [option, option.to_s]
        it "outputs deprecation warning for :#{key} option" do
          Guard::UI.should_receive(:info).with(
            "DEPRECATION WARNING: The :#{key} option is deprecated. Pass standard command line " <<
            %(argument "--#{value}" to RSpec with the :cli option.)
          ).ordered
          described_class.new(key => 'foo')
        end
      end
    end
  end

  describe '#run' do
    context 'when passed an empty paths list' do
      it 'returns false' do
        subject.run([]).should be_false
      end
    end

    context 'in a folder without Bundler' do
      before do
        Dir.stub(:pwd).and_return(@fixture_path.join('empty'))
      end

      it 'runs with RSpec 2 and without bundler' do
        subject.should_receive(:system).with(
          "rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
          '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
        ).and_return(true)

        subject.run(['spec'])
      end
    end

    context 'in RSpec 2 folder with Bundler' do
      before do
        Dir.stub(:pwd).and_return(@fixture_path.join('rspec2'))
      end

      it 'runs with RSpec 2 and with Bundler' do
        subject.should_receive(:system).with(
          "bundle exec rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
          '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
        ).and_return(true)

        subject.run(['spec'])
      end

      describe 'notification' do
        it 'notifies when RSpec fails to execute' do
          subject.should_receive(:rspec_command) { "`exit 1`" }
          Guard::Notifier.should_receive(:notify).with(
            'Failed', :title => 'RSpec results', :image => :failed, :priority => 2
          )

          subject.run(['spec'])
        end

        context 'using DRb' do
          subject { described_class.new(:cli => '--drb') }

          let(:service) {
            service_double = double
            subject.should_receive(:drb_service) { |port|
              service_double.stub(:port) { port }
              service_double
            }

            service_double
          }

          context 'RSpec 2' do
            it 'returns false when RSpec fails to execute' do
              service.should_receive(:run) { 1 }

              subject.run(['spec']).should be_false
            end
            it 'returns true when RSpec succeeds to execute' do
              service.should_receive(:run) { 0 }

              subject.run(['spec']).should be_true
            end
          end

          it 'does not notify when RSpec fails to execute' do
            service.should_receive(:run) { 1 }
            Guard::Notifier.should_not_receive(:notify)

            subject.run(['spec'])
          end

          it 'falls back to the command runner with an inactive server' do
            service.should_receive(:run).and_raise(DRb::DRbConnError)
            subject.should_receive(:run_via_shell)

            subject.run(['spec'])
          end

          it 'defaults to DRb port 8989' do
            service.should_receive(:run) { 0 }
            subject.run(['spec'])
            service.port.should == 8989
          end

          it 'honors RSPEC_DRB' do
            ENV['RSPEC_DRB'] = '12345'
            service.should_receive(:run) { 0 }
            subject.run(['spec'])
            service.port.should == 12345
          end

          it 'honors --drb-port' do
            service.should_receive(:run) { 0 }
            subject.run(['spec'], :cli => '--drb --drb-port 2222')
            service.port.should == 2222
          end
        end

        it 'does not notify that RSpec failed when the specs failed' do
          subject.should_receive(:rspec_command) { "`exit 2`" }
          Guard::Notifier.should_not_receive(:notify)

          subject.run(['spec'])
        end

        it 'does not notify that RSpec failed when the specs pass' do
          subject.should_receive(:rspec_command) { "`exit 0`" }
          Guard::Notifier.should_not_receive(:notify)

          subject.run(['spec'])
        end
      end

      describe 'options' do
        describe 'as parameters override @options' do
          subject { described_class.new(:cli => '--color') }

          it 'runs with rvm exec' do
            subject.should_receive(:system).with(
              'bundle exec rspec --format doc ' <<
              "-r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
              '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
            ).and_return(true)

            subject.run(['spec'], :cli => '--format doc')
          end
        end

        describe ':message is printed' do
          subject { described_class.new(:cli => '--color') }

          it 'runs with rvm exec' do
            ::Guard::UI.should_receive(:info).with('Foo Bar', :reset => true)
            subject.should_receive(:system).and_return(true)

            subject.run(['spec'], :message => 'Foo Bar')
          end
        end

        describe ':rvm' do
          context ":rvm => ['1.8.7', '1.9.2']" do
            subject { described_class.new(:rvm => ['1.8.7', '1.9.2']) }

            it 'runs with rvm exec' do
              subject.should_receive(:system).with(
                'rvm 1.8.7,1.9.2 exec bundle exec rspec -f progress ' <<
                "-r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end
        end

        describe ':zeus' do
          context ":zeus => true" do
            subject { described_class.new(:zeus => true) }

            it 'runs with zeus' do
              subject.should_receive(:system).with('bundle exec zeus rspec ' <<
                "-f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
              '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              )
              subject.run(['spec'])
            end
          end
        end

        describe ':cli' do
          context ":cli => '--color --drb --fail-fast'" do
            subject { described_class.new(:cli => '--color --drb --fail-fast') }

            it 'runs with CLI options passed to RSpec' do
              subject.should_receive(:system).with(
                'bundle exec rspec --color --drb --fail-fast -f progress ' <<
                "-r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end

          it 'use progress formatter by default' do
            subject.should_receive(:system).with(
              "bundle exec rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
              '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
            ).and_return(true)

            subject.run(['spec'])
          end

          context ":cli => '-f doc'" do
            subject { described_class.new(:cli => '-f doc') }

            it 'respects formatter passed in CLI options to RSpec' do
              subject.should_receive(:system).with(
                "bundle exec rspec -f doc -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end

          context ":cli => '-fdoc'" do
            subject { described_class.new(:cli => '-fdoc') }

            it 'respects formatter passed in CLI options to RSpec' do
              subject.should_receive(:system).with(
                "bundle exec rspec -fdoc -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end

          context ":cli => '--format doc'" do
            subject { described_class.new(:cli => '--format doc') }

            it 'respects formatter passed in CLI options to RSpec' do
              subject.should_receive(:system).with(
                "bundle exec rspec --format doc -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end

          context ":cli => '--format=doc'" do
            subject { described_class.new(:cli => '--format=doc') }

            it 'respects formatter passed in CLI options to RSpec' do
              subject.should_receive(:system).with(
                "bundle exec rspec --format=doc -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end
        end

        describe ':bundler' do
          context ':bundler => false' do
            subject { described_class.new(:bundler => false) }

            it 'runs without Bundler' do
              subject.should_receive(:system).with(
                "rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end
        end

        describe ':binstubs' do
          context ':bundler => false, :binstubs => true' do
            subject { described_class.new(:bundler => false, :binstubs => true) }

            it 'runs without Bundler and with binstubs' do
              subject.should_receive(:system).with(
                "bin/rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end

          context ':bundler => true, :binstubs => true' do
            subject { described_class.new(:bundler => true, :binstubs => true) }

            it 'runs without Bundler and binstubs' do
              subject.should_receive(:system).with(
                "bin/rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end

          context ':bundler => true, :binstubs => "dir"' do
            subject { described_class.new(:bundler => true, :binstubs => 'dir') }

            it 'runs without Bundler and binstubs in custom directory' do
              subject.should_receive(:system).with(
                "dir/rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end
        end

        describe ':notification' do
          context ':notification => false' do
            subject { described_class.new(:notification => false) }

            it 'runs without notification formatter' do
              subject.should_receive(:system).with(
                'bundle exec rspec --failure-exit-code 2 spec'
              ).and_return(true)

              subject.run(['spec'])
            end

            it "doesn't notify when specs fails" do
              subject.should_receive(:system) { mock('res', :success? => false, :exitstatus => 2) }
              Guard::Notifier.should_not_receive(:notify)

              subject.run(['spec'])
            end
          end
        end

        describe ':turnip' do
          context ':turnip => true' do
            subject { described_class.new(:turnip => true) }

            it 'runs with Turnip support enabled' do
              subject.should_receive(:system).with(
                "bundle exec rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 -r turnip/rspec spec'
              ).and_return(true)

              subject.run(['spec'])
            end
          end
        end

        describe ':env' do
          context ":env => {'RAILS_ENV' => 'blue'}" do
            subject { described_class.new(:env => {'RAILS_ENV' => 'blue'}) }

            it 'sets the Rails environment' do
              subject.should_receive(:system).with(
                "export RAILS_ENV=blue; bundle exec rspec -f progress -r #{@lib_path.join('guard/rspec/formatter.rb')} " <<
                '-f Guard::RSpec::Formatter --out /dev/null --failure-exit-code 2 spec'
                ).and_return(true)

              subject.run(['spec'])
            end
          end
        end
      end
    end
  end

  describe '#parsed_or_default_formatter' do
    OPTIONS_FILE = /\.rspec/

    def stub_options_file(method, value)
      stub_with_fallback(File, method).with(OPTIONS_FILE).and_return(value)
    end

    let(:formatters) { subject.parsed_or_default_formatter }

    context '.rspec file exists' do
      before do
        Dir.stub(:pwd).and_return(@fixture_path)
        stub_options_file(:exist?, true)
      end

      context 'and includes a --format option' do
        before do
          stub_options_file(:read, "--colour\n--format RSpec::Instafail")
        end

        it 'returns the formatter from .rspec file' do
          formatters.should eq '-f RSpec::Instafail'
        end

        context 'using ERb syntax' do
          before do
            stub_options_file(:read, "--colour\n--format <%= 'doc' + 'umentation' %>")
          end

          it 'evalutes ERb expressions' do
            formatters.should eq '-f documentation'
          end
        end

        context 'while specifying an output file' do
          before do
            stub_options_file(:read, "--format documentation --out doc/specs.txt")
          end

          it 'specifies the output file' do
            formatters.should eq '-f documentation -o doc/specs.txt'
          end
        end
      end

      context 'and includes multiple --format options' do
        before do
          stub_options_file(:read, "--format html --out doc/specs.html " +
                                   "--format progress " +
                                   "--format documentation --out doc/specs.txt")
        end

        it 'returns all the formatters from .rspec file' do
          formatters.should include('-f html', '-f progress', '-f documentation')
        end

        it 'returns the output files for the specified formatters' do
          formatters.should include('-f html -o doc/specs.html',
                                    '-f documentation -o doc/specs.txt')
          formatters.should_not include('-f progress -o')
        end
      end

      context 'but doesn\'t include a --format option' do
        before do
          stub_options_file(:read, "--colour")
        end

        it 'returns progress formatter' do
          formatters.should eq '-f progress'
        end

        context 'yet includes a --out option' do
          before do
            stub_options_file(:read, "--out /dev/null")
          end

          it 'returns progress formatter with the output file option' do
            formatters.should eq '-f progress -o /dev/null'
          end
        end
      end

      context 'but includes a commented --format option' do
        before do
          stub_options_file(:read, "--colour\n<%# '--format documentation' %>")
        end

        it 'ignores the commented option' do
          formatters.should_not include('documentation')
        end
      end
    end

    context '.rspec file doesn\'t exists' do
      before { stub_options_file(:exist?, false) }

      it 'returns progress formatter' do
        formatters.should eq '-f progress'
      end
    end
  end

end
