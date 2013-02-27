Redis::Objects - Map Redis types directly to Ruby objects
=========================================================

This is **not** an ORM. People that are wrapping ORM’s around Redis are missing the point.

The killer feature of Redis is that it allows you to perform _atomic_ operations
on _individual_ data structures, like counters, lists, and sets.  The **atomic** part is HUGE.
Using an ORM wrapper that retrieves a "record", updates values, then sends those values back,
_removes_ the atomicity, cutting the nuts off the major advantage of Redis.  Just use MySQL, k?

This gem provides a Rubyish interface to Redis, by mapping [Redis types](http://redis.io/commands)
to Ruby objects, via a thin layer over the `redis` gem.  It offers several advantages
over the lower-level redis-rb API:

1. Easy to integrate directly with existing ORMs - ActiveRecord, DataMapper, etc.  Add counters to your model!
2. Complex data structures are automatically Marshaled (if you set :marshal => true)
3. Integers are returned as integers, rather than '17'
4. Higher-level types are provided, such as Locks, that wrap multiple calls

This gem originally arose out of a need for high-concurrency atomic operations;
for a fun rant on the topic, see [An Atomic Rant](http://nateware.com/2010/02/18/an-atomic-rant),
or scroll down to [Atomic Counters and Locks](#atomicity) in this README.

There are two ways to use Redis::Objects, either as an include in a model class (to
integrate with ORMs or other classes), or by using new with the type of data structure
you want to create. 

Installation and Setup
----------------------
Add it to your Gemfile as:

    gem 'redis-objects'

**Redis::Objects** needs a handle created by `Redis.new`. The recommended approach
is to set `Redis.current` to point to your server, which **Redis::Objects** will
pick up automatically.

    require 'redis/objects'
    Redis.current = Redis.new(:host => '127.0.0.1', :port => 6379)

(If you're on Rails, `config/initializers/redis.rb` is a good place for this.)
Remember you can use **Redis::Objects** in any Ruby code.  There are **no** dependencies
on Rails.  Standalone, Sinatra, Resque - no problem.

Alternatively, you can set the `redis` handle directly:

    Redis::Objects.redis = Redis.new(...)

Finally, you can even setup different handles for different classes:

    class User
      include Redis::Objects
    end
    class Post
      include Redis::Objects
    end

    User.redis = Redis.new(...)
    Post.redis = Redis.new(...)

As of `0.7.0`, `redis-objects` now autoloads the appropriate `Redis::Whatever`
classes on demand.  Previous strategies of individually requiring `redis/list`
or `redis/set` are no longer required.

There are two ways to use **Redis::Objects**: As part of an model class (ActiveRecord,
DataMapper, Mongoid, etc) or as standalong data type classes (`Redis::Set`, `Redis::List`, etc).

Option 1: Model Class Usage
============================
Using Redis::Objects this way makes it trivial to integrate Redis types with an
existing ActiveRecord model, DataMapper resource, or other class.  **Redis::Objects**
will work with _any_ class that provides an `id` method that returns a unique
value.  **Redis::Objects** will then automatically create keys that are unique to
each object, in the format:

    model_name:id:field_name

For illustration purposes, consider this stub class:

    class User
      include Redis::Objects
      counter :my_posts
      def id
        1
      end
    end

    user = User.new
    user.id  # 1
    user.my_posts.increment
    user.my_posts.increment
    user.my_posts.increment
    puts user.my_posts  # 3

You can include Redis::Objects in any type of class:

    class Team < ActiveRecord::Base
      include Redis::Objects

      lock :trade_players, :expiration => 15  # sec
      value :at_bat
      counter :hits
      counter :runs
      counter :outs
      counter :inning, :start => 1
      list :on_base
      list :coaches, :marshal => true
      set  :outfielders
      hash_key :pitchers_faced  # "hash" is taken by Ruby
      sorted_set :rank, :global => true
    end

Familiar Ruby array operations Just Work (TM):

    @team = Team.find_by_name('New York Yankees')
    @team.on_base << 'player1'
    @team.on_base << 'player2'
    @team.on_base << 'player3'
    @team.on_base    # ['player1', 'player2', 'player3']
    @team.on_base.pop
    @team.on_base.shift
    @team.on_base.length  # 1
    @team.on_base.delete('player2')

Sets work too:

    @team.outfielders << 'outfielder1'
    @team.outfielders << 'outfielder2'
    @team.outfielders << 'outfielder1'   # dup ignored
    @team.outfielders  # ['outfielder1', 'outfielder2']
    @team.outfielders.each do |player|
      puts player
    end
    player = @team.outfielders.detect{|of| of == 'outfielder2'}

And you can do intersections between objects (kinda cool):

    @team1.outfielders | @team2.outfielders   # outfielders on both teams
    @team1.outfielders & @team2.outfielders   # in baseball, should be empty :-)

Counters can be atomically incremented/decremented (but not assigned):

    @team.hits.increment  # or incr
    @team.hits.decrement  # or decr
    @team.hits.incr(3)    # add 3
    @team.runs = 4        # exception

Finally, for free, you get a `redis` method that points directly to a Redis connection:

    Team.redis.get('somekey')
    @team = Team.new
    @team.redis.get('somekey')
    @team.redis.smembers('someset')

You can use the `redis` handle to directly call any [Redis API command](http://redis.io/commands).

Option 2: Standalone Usage
===========================
There is a Ruby class that maps to each Redis type, with methods for each
[Redis API command](http://redis.io/commands).
Note that calling `new` does not imply it's actually a "new" value - it just
creates a mapping between that Ruby object and the corresponding Redis data
structure, which may already exist on the `redis-server`.

Counters
--------
The `counter_name` is the key stored in Redis.

    @counter = Redis::Counter.new('counter_name')
    @counter.increment  # or incr
    @counter.decrement  # or decr
    @counter.increment(3)
    puts @counter.value

This gem provides a clean way to do atomic blocks as well:

    @counter.increment do |val|
      raise "Full" if val > MAX_VAL  # rewind counter
    end

See the section on [Atomic Counters and Locks](#atomicity) for cool uses of atomic counter blocks.

Locks
-----
A convenience class that wraps the pattern of [using setnx to perform locking](http://redis.io/commands/setnx).

    @lock = Redis::Lock.new('serialize_stuff', :expiration => 15, :timeout => 0.1)
    @lock.lock do
      # do work
    end

This can be especially useful if you're running batch jobs spread across multiple hosts.

Values
------
Simple values are easy as well:

    @value = Redis::Value.new('value_name')
    @value.value = 'a'
    @value.delete

Complex data is no problem with :marshal => true:

    @account = Account.create!(params[:account])
    @newest  = Redis::Value.new('newest_account', :marshal => true)
    @newest.value = @account.attributes
    puts @newest.value['username']

Lists
-----
Lists work just like Ruby arrays:

    @list = Redis::List.new('list_name')
    @list << 'a'
    @list << 'b'
    @list.include? 'c'   # false
    @list.values  # ['a','b']
    @list << 'c'
    @list.delete('c')
    @list[0]
    @list[0,1]
    @list[0..1]
    @list.shift
    @list.pop
    @list.clear
    # etc

You can bound the size of the list to only hold N elements like so:

    # Only holds 10 elements, throws out old ones when you reach :maxlength.
    @list = Redis::List.new('list_name', :maxlength => 10)

Complex data types are no handled with :marshal => true:

    @list = Redis::List.new('list_name', :marshal => true)
    @list << {:name => "Nate", :city => "San Diego"}
    @list << {:name => "Peter", :city => "Oceanside"}
    @list.each do |el|
      puts "#{el[:name]} lives in #{el[:city]}"
    end

Hashes
------
Hashes work like a Ruby [Hash](http://ruby-doc.org/core/classes/Hash.html), with
a few Redis-specific additions.  (The class name is "HashKey" not just "Hash", due to
conflicts with the Ruby core Hash class in other gems.)

    @hash = Redis::HashKey.new('hash_name')
    @hash['a'] = 1
    @hash['b'] = 2
    @hash.each do |k,v|
      puts "#{k} = #{v}"
    end
    @hash['c'] = 3
    puts @hash.all  # {"a"=>"1","b"=>"2","c"=>"3"}
    @hash.clear

Redis also adds incrementing and bulk operations:

    @hash.incr('c', 6)  # 9
    @hash.bulk_set('d' => 5, 'e' => 6)
    @hash.bulk_get('d','e')  # "5", "6"

Remember that numbers become strings in Redis.  Unlike with other Redis data types,
`redis-objects` can't guess at your data type in this situation, since you may
actually mean to store "1.5".

Sets
----
Sets work like the Ruby [Set](http://ruby-doc.org/core/classes/Set.html) class.
They are unordered, but guarantee uniqueness of members.

    @set = Redis::Set.new('set_name')
    @set << 'a'
    @set << 'b'
    @set << 'a'  # dup ignored
    @set.member? 'c'      # false
    @set.members          # ['a','b']
    @set.members.reverse  # ['b','a']
    @set.each do |member|
      puts member
    end
    @set.clear
    # etc

You can perform Redis intersections/unions/diffs easily:

    @set1 = Redis::Set.new('set1')
    @set2 = Redis::Set.new('set2')
    @set3 = Redis::Set.new('set3')
    members = @set1 & @set2   # intersection
    members = @set1 | @set2   # union
    members = @set1 + @set2   # union
    members = @set1 ^ @set2   # difference
    members = @set1 - @set2   # difference
    members = @set1.intersection(@set2, @set3)  # multiple
    members = @set1.union(@set2, @set3)         # multiple
    members = @set1.difference(@set2, @set3)    # multiple

Or store them in Redis:

    @set1.interstore('intername', @set2, @set3)
    members = @set1.redis.get('intername')
    @set1.unionstore('unionname', @set2, @set3)
    members = @set1.redis.get('unionname')
    @set1.diffstore('diffname', @set2, @set3)
    members = @set1.redis.get('diffname')

And use complex data types too, with :marshal => true:

    @set1 = Redis::Set.new('set1', :marshal => true)
    @set2 = Redis::Set.new('set2', :marshal => true)
    @set1 << {:name => "Nate",  :city => "San Diego"}
    @set1 << {:name => "Peter", :city => "Oceanside"}
    @set2 << {:name => "Nate",  :city => "San Diego"}
    @set2 << {:name => "Jeff",  :city => "Del Mar"}

    @set1 & @set2  # Nate
    @set1 - @set2  # Peter
    @set1 | @set2  # all 3 people

Sorted Sets
-----------
Due to their unique properties, Sorted Sets work like a hybrid between
a Hash and an Array.  You assign like a Hash, but retrieve like an Array:

    @sorted_set = Redis::SortedSet.new('number_of_posts')
    @sorted_set['Nate']  = 15
    @sorted_set['Peter'] = 75
    @sorted_set['Jeff']  = 24

    # Array access to get sorted order
    @sorted_set[0..2]           # => ["Nate", "Jeff", "Peter"]
    @sorted_set[0,2]            # => ["Nate", "Jeff"]

    @sorted_set['Peter']        # => 75
    @sorted_set['Jeff']         # => 24
    @sorted_set.score('Jeff')   # same thing (24)

    @sorted_set.rank('Peter')   # => 2
    @sorted_set.rank('Jeff')    # => 1

    @sorted_set.first           # => "Nate"
    @sorted_set.last            # => "Peter"
    @sorted_set.revrange(0,2)   # => ["Peter", "Jeff", "Nate"]

    @sorted_set['Newbie'] = 1
    @sorted_set.members         # => ["Newbie", "Nate", "Jeff", "Peter"]
    @sorted_set.members.reverse # => ["Peter", "Jeff", "Nate", "Newbie"]

    @sorted_set.rangebyscore(10, 100, :limit => 2)   # => ["Nate", "Jeff"]
    @sorted_set.members(:with_scores => true)        # => [["Newbie", 1], ["Nate", 16], ["Jeff", 28], ["Peter", 76]]

    # atomic increment
    @sorted_set.increment('Nate')
    @sorted_set.incr('Peter')   # shorthand
    @sorted_set.incr('Jeff', 4)

The other Redis Sorted Set commands are supported as well; see [Sorted Sets API](http://redis.io/commands#sorted_set).

<a name="atomicity"></a>
Atomic Counters and Locks
-------------------------
You are probably not handling atomicity correctly in your app.  For a fun rant
on the topic, see [An Atomic Rant](http://nateware.com/an-atomic-rant.html).

Atomic counters are a good way to handle concurrency:

    @team = Team.find(1)
    if @team.drafted_players.increment <= @team.max_players
      # do stuff
      @team.team_players.create!(:player_id => 221)
      @team.active_players.increment
    else
      # reset counter state
      @team.drafted_players.decrement
    end

An _atomic block_ gives you a cleaner way to do the above. Exceptions or returning nil
will rewind the counter back to its previous state:

    @team.drafted_players.increment do |val|
      raise Team::TeamFullError if val > @team.max_players  # rewind
      @team.team_players.create!(:player_id => 221)
      @team.active_players.increment
    end

Here's a similar approach, using an if block (failure rewinds counter):

    @team.drafted_players.increment do |val|
      if val <= @team.max_players
        @team.team_players.create!(:player_id => 221)
        @team.active_players.increment
      end
    end

Class methods work too, using the familiar ActiveRecord counter syntax:

    Team.increment_counter :drafted_players, team_id
    Team.decrement_counter :drafted_players, team_id, 2
    Team.increment_counter :total_online_players  # no ID on global counter

Class-level atomic blocks can also be used.  This may save a DB fetch, if you have
a record ID and don't need any other attributes from the DB table:

    Team.increment_counter(:drafted_players, team_id) do |val|
      TeamPitcher.create!(:team_id => team_id, :pitcher_id => 181)
      Team.increment_counter(:active_players, team_id)
    end

### Locks ###

Locks work similarly. On completion or exception the lock is released:

    class Team < ActiveRecord::Base
      lock :reorder # declare a lock
    end

    @team.reorder_lock.lock do
      @team.reorder_all_players
    end

Class-level lock (same concept)

    Team.obtain_lock(:reorder, team_id) do
      Team.reorder_all_players(team_id)
    end

Lock expiration.  Sometimes you want to make sure your locks are cleaned up should
the unthinkable happen (server failure).  You can set lock expirations to handle
this.  Expired locks are released by the next process to attempt lock.  Just
make sure you expiration value is sufficiently large compared to your expected
lock time.

    class Team < ActiveRecord::Base
      lock :reorder, :expiration => 15.minutes
    end

Keep in mind that true locks serialize your entire application at that point.  As
such, atomic counters are strongly preferred.

Author
=======
Copyright (c) 2009-2013 [Nate Wiger](http://nateware.com).  All Rights Reserved.
Released under the [Artistic License](http://www.opensource.org/licenses/artistic-license-2.0.php).
