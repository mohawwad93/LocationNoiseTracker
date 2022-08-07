import 'package:graphql_flutter/graphql_flutter.dart';

const String _endpoint = 'just-pegasus-83.hasura.app/v1/graphql';
const String _token = "iXay4bvNxM8cNYLzvudlGp7YU3xJvnJd8FOa1OEYfdG6DC00HxpugUhcUwr2Mv8h";

Future<GraphQLClient> get gqlClient async{
  await initHiveForFlutter();
  final HttpLink _httpLink = HttpLink('https://$_endpoint',
      defaultHeaders: {
        'x-hasura-admin-secret': _token
      }
  );
  final WebSocketLink _wsLink = WebSocketLink('wss://$_endpoint',
    config: const SocketClientConfig(
      autoReconnect: true,
      inactivityTimeout: Duration(seconds: 30),
      headers: {
        'x-hasura-admin-secret': _token
      }
    ),
  );
  Link _link = Link.split((request) => request.isSubscription, _wsLink, _httpLink);
  GraphQLClient client = GraphQLClient(
    cache: GraphQLCache(store: HiveStore()),
    link: _link,
  );
  return client;
}