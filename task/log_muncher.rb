require 'damerau-levenshtein'

class BKTree
  def initialize
    @root = nil
    @distance_calculator = DamerauLevenshtein.method(:distance)
  end

  def insert(word)
    if @root.nil?
      @root = Node.new(word)
    else
      @root.add(word, @distance_calculator)
    end
  end

  def search(word, max_distance)
    return [] if @root.nil?

    @root.find_similar(word, max_distance, @distance_calculator)
  end

  class Node
    attr_reader :word, :children

    def initialize(word)
      @word = word
      @children = {}
    end

    def add(new_word, distance_calculator)
      distance = distance_calculator.call(@word, new_word)

      if @children[distance]
        @children[distance].add(new_word, distance_calculator)
      else
        @children[distance] = Node.new(new_word)
      end
    end

    def find_similar(target, max_distance, distance_calculator)
      distance_to_node = distance_calculator.call(@word, target)
      results = []
      results << @word if distance_to_node <= max_distance

      lower_bound = distance_to_node - max_distance
      upper_bound = distance_to_node + max_distance

      @children.each do |distance, child|
        if distance.between?(lower_bound, upper_bound)
          results.concat(child.find_similar(target, max_distance, distance_calculator))
        end
      end

      results
    end
  end
end

class ElectionLogProcessor
  def initialize(log_file)
    @log_file = log_file
    @votes = Hash.new(0)
    @bk_tree = BKTree.new
    @name_frequencies = Hash.new(0)
  end

  def normalize_name(name)
    cleaned = name.gsub(/[a-zA-Z]/, '')
    cleaned.gsub(/([a-zа-я])([A-ZА-Я])/, '\1 \2')
  end

  def process_logs
    File.foreach(@log_file) do |line|
      if line =~ /vote\s*=>\s*(.+)/
        candidate_name = normalize_name($1.strip)
        closest_name = find_closest_name(candidate_name)

        if closest_name.nil?
          @bk_tree.insert(candidate_name)
          @votes[candidate_name] += 1
          @name_frequencies[candidate_name] += 1
        else
          handle_vote(candidate_name, closest_name)
        end
      end
    end
  end

  def find_closest_name(name)
    candidates = @bk_tree.search(name, 2)
    candidates.min_by { |candidate| [DamerauLevenshtein.distance(name, candidate), -candidate.length] }
  end

  def handle_vote(candidate_name, closest_name)
    distance = DamerauLevenshtein.distance(candidate_name, closest_name)
    if distance <= 2
      if candidate_name.length > closest_name.length
        @votes[candidate_name] += @votes.delete(closest_name)
        @votes[candidate_name] += 1
        @name_frequencies[candidate_name] += 1
        @bk_tree.insert(candidate_name)
      else
        @votes[closest_name] += 1
        @name_frequencies[closest_name] += 1
      end
    else
      @votes[candidate_name] += 1
      @name_frequencies[candidate_name] += 1
    end
  end

  def consolidate_votes
    name_map = {}
    @name_frequencies.keys.each do |name|
      next if name_map[name]

      similar_names = find_similar_names(name)
      representative_name = select_representative(similar_names)

      similar_names.each { |similar_name| name_map[similar_name] = representative_name }
    end

    consolidated = Hash.new(0)
    @votes.each do |name, count|
      representative = name_map[name] || name
      consolidated[representative] += count
    end

    consolidated
  end

  def find_similar_names(name)
    @name_frequencies.keys.select { |candidate| DamerauLevenshtein.distance(name, candidate) <= 2 }
  end

  def select_representative(names)
    names.max_by { |name| [@name_frequencies[name], name.length] }
  end

  def display_results
    consolidated = consolidate_votes
    sorted_results = consolidated.sort_by { |_, votes| -votes }

    sorted_results.each { |name, votes| puts "#{name}: #{votes} голосов" }

    total_votes = consolidated.values.sum
    puts "\nВсего голосов: #{total_votes}"
  end
end

processor = ElectionLogProcessor.new('data/log.txt')
processor.process_logs
processor.display_results
