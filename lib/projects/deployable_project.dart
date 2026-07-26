class DeployableProject {
  final String projectId;
  final String name;
  final String path;

  const DeployableProject({
    required this.projectId,
    required this.name,
    required this.path,
  });

  factory DeployableProject.fromJson(Map<String, dynamic> json) {
    return DeployableProject(
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'name': name,
        'path': path,
      };
}
