__constant__ int NUM_POSITIONS = 8;

__constant__ int POWER = 0;
__constant__ int ANGEL = 1;

__constant__ int DIMS = 2;

__constant__ int SYMMETRY_ORDER = 4;

__constant__ int NORTH = 0;
__constant__ int EAST  = 1;
__constant__ int SOUTH = 2;
__constant__ int WEST  = 3;

__constant__ int LEFT  = 1;
__constant__ int RIGHT = 2;

__constant__ int FORWARD = 1;

extern "C" {
  // Device helper function to rotate coordinates
  __device__ void RotateCoordinates(
    int kSpaceLength,
    int orientation,
    int * loc_y,
    int * loc_x
  ) {
    int loc_y_tmp = *loc_y;
    int loc_x_tmp = *loc_x;
    if (orientation == NORTH) {
      *loc_y = loc_y_tmp;
      *loc_x = loc_x_tmp;
    } else if (orientation == EAST) {
      *loc_y = kSpaceLength - 1 - loc_x_tmp;
      *loc_x = loc_y_tmp;
    } else if (orientation == SOUTH) {
      *loc_y = kSpaceLength - 1 - loc_y_tmp;
      *loc_x = kSpaceLength - 1 - loc_x_tmp;
    } else if (orientation == WEST) {
      *loc_y = loc_x_tmp;
      *loc_x = kSpaceLength - 1 - loc_y_tmp;
    }
  }

  // Device helper function to check whether a point is within bounds
  __device__ bool PointIsWithinBounds(
    int kSpaceLength,
    int loc_y,
    int loc_x
  ) {
    return (0 <= loc_y && loc_y < kSpaceLength && 0 <= loc_x && loc_x < kSpaceLength);
  }

  // Device helper function to check whether a point is occupied
  __device__ bool PointIsOccupied(
    int * loc_y_arr,
    int * loc_x_arr,
    int kNumAgents,
    int kEnvId,
    int kThisAgentId,
    int loc_y,
    int loc_x
  ) {
    for (int kAgentId = 0; kAgentId < kNumAgents; kAgentId++) {
      if (kAgentId != kThisAgentId) {
        int kAgentIdx = kEnvId * kNumAgents + kAgentId;
        if (loc_y_arr[kAgentIdx] == loc_y && loc_x_arr[kAgentIdx] == loc_x) {
          return true;
        }
      }
    }
    return false;
  }

  // Device helper function to generate an unoccupied point
  __device__ void GenerateUnoccupiedPoint(
    int kSpaceLength,
    int * loc_y_arr,
    int * loc_x_arr,
    int kNumAgents,
    int kEnvId,
    int * loc_y,
    int * loc_x
  ) {
    // Use last agent's state to generate a random point
    curandState_t* state = states[kEnvId * kNumAgents + kNumAgents - 1];
    do {
      // Generate random coordinates from uniform distribution over [0, kSpaceLength - 1]
      *loc_y = kSpaceLength * (1.0 - curand_uniform(state));
      *loc_x = kSpaceLength * (1.0 - curand_uniform(state));
    } while (PointIsOccupied(
      loc_y_arr,
      loc_x_arr,
      kNumAgents,
      kEnvId,
      -1,
      *loc_y,
      *loc_x
    ));
  }

  // Device helper function to compute rewards
  __device__ void CudaBlessedRealmComputeReward(
    int * loc_y_arr,
    int * loc_x_arr,
    int * goal_point_arr,
    float * rewards_arr,
    int * done_arr,
    int * env_timestep_arr,
    int kNumAgents,
    int kEpisodeLength,
    const int kEnvId,
    const int kThisAgentId,
    const int kThisAgentArrayIdx
  ) {
    if (kThisAgentId < kNumAgents) {
      // Initialize rewards
      rewards_arr[kThisAgentArrayIdx] = 0.0;

      // Check whether the agent has reached the goal
      if (loc_y_arr[kThisAgentArrayIdx] == goal_point_arr[kEnvId * DIMS    ] &&
          loc_x_arr[kThisAgentArrayIdx] == goal_point_arr[kEnvId * DIMS + 1]) {
        // rewards_arr[kThisAgentArrayIdx] = 1.0 * (1.0 - env_timestep_arr[kEnvId] / float(kEpisodeLength));
        float reward = 1.0 * (1.0 - env_timestep_arr[kEnvId] / float(kEpisodeLength));
        for (int kAgentId = 0; kAgentId < kNumAgents; kAgentId++) {
          int kAgentIdx = kEnvId * kNumAgents + kAgentId;
          rewards_arr[kAgentIdx] = reward;
        }
        // done_arr[kEnvId] = 1;
      }

      // Use only last agent's thread to check whether the maximum number of timesteps has been reached
      if (kThisAgentId == kNumAgents - 1) {
        if (env_timestep_arr[kEnvId] == kEpisodeLength) {
            done_arr[kEnvId] = 1;
        }
      }
    }
  }

  // Device helper function to generate observation
  __device__ void CudaBlessedRealmGenerateObservation(
    int kSpaceLength,
    int * loc_y_arr,
    int * loc_x_arr,
    int * orientation_arr,
    int * agent_types_arr,
    int * goal_point_arr,
    float * obs_arr,
    int * action_indices_arr,
    int * done_arr,
    int * env_timestep_arr,
    const int kNumAgents,
    const int kEpisodeLength,
    const int kEnvId,
    const int kThisAgentId,
    const int kThisAgentArrayIdx,
    const int kNumActions
  ) {
    if (kThisAgentId < kNumAgents) {
      // obs shape is (num_envs, kNumAgents, n)
      const int n = 5 + NUM_POSITIONS;
      const int kThisAgentIdxOffset = (kEnvId * kNumAgents + kThisAgentId) * n;
      const int kThatAgentId = (kThisAgentId + 1) % kNumAgents;
      const int kThatAgentArrayIdx = kEnvId * kNumAgents + kThatAgentId;
      const int kThatAgentActionIdxOffset = kEnvId * kNumAgents * kNumActions + kThatAgentId * kNumActions;

      // Initialize obs
      for (int i = 0; i < n; i++) {
        obs_arr[kThisAgentIdxOffset + i] = 0.0;
      }

      int kAgentIdx;
      int loc_y;
      int loc_x;
      if (done_arr[kEnvId]) {
        // Reinitialize agent points
        for (int kAgentId = 0; kAgentId < kNumAgents; kAgentId++) {
          kAgentIdx = kEnvId * kNumAgents + kAgentId;
          loc_y_arr[kAgentIdx] = -1;
          loc_x_arr[kAgentIdx] = -1;
        }

        // Reset agent points
        for (int kAgentId = 0; kAgentId < kNumAgents; kAgentId++) {
          kAgentIdx = kEnvId * kNumAgents + kAgentId;
          GenerateUnoccupiedPoint(
            kSpaceLength,
            loc_y_arr,
            loc_x_arr,
            kNumAgents,
            kEnvId,
            &loc_y,
            &loc_x
          );
          loc_y_arr[kAgentIdx] = loc_y;
          loc_x_arr[kAgentIdx] = loc_x;
        }

        // Reset goal point
        GenerateUnoccupiedPoint(
          kSpaceLength,
          loc_y_arr,
          loc_x_arr,
          kNumAgents,
          kEnvId,
          &loc_y,
          &loc_x
        );
        goal_point_arr[kEnvId * DIMS    ] = loc_y;
        goal_point_arr[kEnvId * DIMS + 1] = loc_x;

        // Reset agent orientations
        for (int kAgentId = 0; kAgentId < kNumAgents; kAgentId++) {
          kAgentIdx = kEnvId * kNumAgents + kAgentId;
          // Use agent's state to generate a random orientation
          curandState_t* state = states[kAgentIdx];
          // Generate a random orientation from uniform distribution over [0, SYMMETRY_ORDER - 1]
          orientation_arr[kAgentIdx] = SYMMETRY_ORDER * (1.0 - curand_uniform(state));
        }
      }

      if (agent_types_arr[kThisAgentId] == POWER) {
        loc_y = loc_y_arr[kThatAgentArrayIdx];
        loc_x = loc_x_arr[kThatAgentArrayIdx];
        RotateCoordinates(kSpaceLength, orientation_arr[kThatAgentArrayIdx], &loc_y, &loc_x);
        obs_arr[kThisAgentIdxOffset    ] = loc_y;
        obs_arr[kThisAgentIdxOffset + 1] = loc_x;

        loc_y = goal_point_arr[kEnvId * DIMS    ];
        loc_x = goal_point_arr[kEnvId * DIMS + 1];
        RotateCoordinates(kSpaceLength, orientation_arr[kThatAgentArrayIdx], &loc_y, &loc_x);
        obs_arr[kThisAgentIdxOffset + 2] = loc_y - obs_arr[kThisAgentIdxOffset    ];
        obs_arr[kThisAgentIdxOffset + 3] = loc_x - obs_arr[kThisAgentIdxOffset + 1];
        obs_arr[kThisAgentIdxOffset + 4] = orientation_arr[kThatAgentArrayIdx];
      } else {
        for (int position = 0; position < NUM_POSITIONS; position++) {
          obs_arr[kThisAgentIdxOffset + 5 + position] = action_indices_arr[kThatAgentActionIdxOffset + 2 + position];
        }
      }
    }
  }

  __global__ void CudaBlessedRealmStep(
    const bool kMarred,
    int kRadius,
    int * loc_y_arr,
    int * loc_x_arr,
    int * orientation_arr,
    int * agent_types_arr,
    int * goal_point_arr,
    float * obs_arr,
    int * action_indices_arr,
    float * rewards_arr,
    int * done_arr,
    int * env_timestep_arr,
    int kNumAgents,
    int kEpisodeLength
  ) {
    const int kEnvId = getEnvID(blockIdx.x);
    const int kThisAgentId = getAgentID(threadIdx.x, blockIdx.x, blockDim.x);
    const int kThisAgentArrayIdx = kEnvId * kNumAgents + kThisAgentId;
    const int kNumActions = 2 + NUM_POSITIONS;
    const int kThisAgentActionIdxOffset = kEnvId * kNumAgents * kNumActions + kThisAgentId * kNumActions;
    const int kSpaceLength = 2*kRadius + 1;

    if (agent_types_arr[kThisAgentId] == ANGEL) {

      int action_turn = action_indices_arr[kThisAgentActionIdxOffset    ];
      int action_move = action_indices_arr[kThisAgentActionIdxOffset + 1];

      int loc_y_tmp = loc_y_arr[kThisAgentArrayIdx];
      int loc_x_tmp = loc_x_arr[kThisAgentArrayIdx];

      if (action_move == FORWARD) {
        if        (orientation_arr[kThisAgentArrayIdx] == NORTH) {
          loc_y_tmp -= 1;
        } else if (orientation_arr[kThisAgentArrayIdx] == EAST ) {
          loc_x_tmp += 1;
        } else if (orientation_arr[kThisAgentArrayIdx] == SOUTH) {
          loc_y_tmp += 1;
        } else if (orientation_arr[kThisAgentArrayIdx] == WEST ) {
          loc_x_tmp -= 1;
        }
      } else if (action_turn == LEFT) {
        orientation_arr[kThisAgentArrayIdx] = (orientation_arr[kThisAgentArrayIdx] + SYMMETRY_ORDER - 1) % SYMMETRY_ORDER;
      } else if (action_turn == RIGHT) {
        orientation_arr[kThisAgentArrayIdx] = (orientation_arr[kThisAgentArrayIdx] +                  1) % SYMMETRY_ORDER;
      }

      if (
        PointIsWithinBounds(
          kSpaceLength,
          loc_y_tmp,
          loc_x_tmp
        )  // && !PointIsOccupied(
        //   loc_y_arr,
        //   loc_x_arr,
        //   kNumAgents,
        //   kEnvId,
        //   kThisAgentId,
        //   loc_y_tmp,
        //   loc_x_tmp
        // )
      ) {
        // Update the point of the agent
        loc_y_arr[kThisAgentArrayIdx] = loc_y_tmp;
        loc_x_arr[kThisAgentArrayIdx] = loc_x_tmp;
      }
    }

    // Wait here until timestep has been updated
    if (kThisAgentId == 0) {
      env_timestep_arr[kEnvId] += 1;
    }

    // Make sure all agents have updated their states
    __sync_env_threads();

    assert(0 < env_timestep_arr[kEnvId] && env_timestep_arr[kEnvId] <= kEpisodeLength);

    // -------------------------------
    // Compute reward
    // -------------------------------
    CudaBlessedRealmComputeReward(
      loc_y_arr,
      loc_x_arr,
      goal_point_arr,
      rewards_arr,
      done_arr,
      env_timestep_arr,
      kNumAgents,
      kEpisodeLength,
      kEnvId,
      kThisAgentId,
      kThisAgentArrayIdx
    );

    // -------------------------------
    // Generate observation
    // -------------------------------
    CudaBlessedRealmGenerateObservation(
      kSpaceLength,
      loc_y_arr,
      loc_x_arr,
      orientation_arr,
      agent_types_arr,
      goal_point_arr,
      obs_arr,
      action_indices_arr,
      done_arr,
      env_timestep_arr,
      kNumAgents,
      kEpisodeLength,
      kEnvId,
      kThisAgentId,
      kThisAgentArrayIdx,
      kNumActions
    );
  }
}
