-module(erldns_metrics).

-behavior(gen_server).

-export([start_link/0]).

-export([setup/0, metrics/0, stats/0, filtered_stats/0]).

-define(DEFAULT_PORT, 8082).

% Gen server hooks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
  ]).

-record(state, {}).

%% Not part of gen server

setup() ->
  folsom_metrics:new_histogram(udp_handoff_histogram),
  folsom_metrics:new_histogram(tcp_handoff_histogram),

  folsom_metrics:new_counter(request_throttled_counter),
  folsom_metrics:new_meter(request_throttled_meter),
  folsom_metrics:new_histogram(request_handled_histogram),

  folsom_metrics:new_meter(cache_hit_meter),
  folsom_metrics:new_meter(cache_expired_meter),
  folsom_metrics:new_meter(cache_miss_meter),

  folsom_metrics:get_metrics().

metrics() ->
  lists:map(
    fun(Name) ->
        {Name, folsom_metrics:get_metric_value(Name)}
    end, folsom_metrics:get_metrics()).

stats() ->
  Histograms = [udp_handoff_histogram, tcp_handoff_histogram, request_handled_histogram],
  lists:map(
    fun(Name) ->
        {Name, folsom_metrics:get_histogram_statistics(Name)}
    end, Histograms).

filtered_stats() ->
  filter_stats(stats()).

% Functions to clean up the stats so they can be returned as JSON.
filter_stats(Stats) ->
  filter_stats(Stats, []).

filter_stats([], FilteredStats) ->
  FilteredStats;
filter_stats([{Name, Stats}|Rest], FilteredStats) ->
  filter_stats(Rest, FilteredStats ++ [{Name, filter_stat_set(Stats)}]).

filter_stat_set(Stats) ->
  filter_stat_set(Stats, []).

filter_stat_set([], FilteredStatSet) ->
  FilteredStatSet;
filter_stat_set([{percentile, Percentiles}|Rest], FilteredStatSet) ->
  filter_stat_set(Rest, FilteredStatSet ++ [{percentile, keys_to_strings(Percentiles)}]);
filter_stat_set([{histogram, _}|Rest], FilteredStatSet) ->
  filter_stat_set(Rest, FilteredStatSet);
filter_stat_set([Pair|Rest], FilteredStatSet) ->
  filter_stat_set(Rest, FilteredStatSet ++ [Pair]).

keys_to_strings(Pairs) ->
  lists:map(
    fun({K, V}) ->
        {list_to_binary(lists:flatten(io_lib:format("~p", [K]))), V}
    end, Pairs).

%% Gen server
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
  lager:debug("Starting ~p", [?MODULE]),

  Dispatch = cowboy_router:compile(
    [
      {'_', 
        [
          {"/", erldns_metrics_root_handler, []}
        ]
      }
    ]
  ),

  {ok, _} = cowboy:start_http(http, 10, [{port, port()}], [{env, [{dispatch, Dispatch}]}]),

  {ok, #state{}}.

handle_call(_Message, _From, State) ->
  {reply, ok, State}.
handle_cast(_, State) ->
  {noreply, State}.
handle_info(_, State) ->
  {noreply, State}.
terminate(_, _) ->
  ok.
code_change(_PreviousVersion, State, _Extra) ->
  {ok, State}.

port() ->
 proplists:get_value(port, metrics_env(), ?DEFAULT_PORT).

metrics_env() ->
  case application:get_env(erldns, metrics) of
    {ok, MetricsEnv} -> MetricsEnv;
    _ -> []
  end.