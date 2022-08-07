const insertLocationNoise = '''
  mutation insert_location_noise(\$longitude: float8, \$latitude: float8, \$noise: float8) {
    insert_location_noise_log_one(object: {latitude: \$latitude, longitude: \$longitude, noise: \$noise}) {
      id
    }
  }
''';