import gym
import numpy as np

from .utils.tilings import SquareTiling


class Realm(gym.Env):

    TURN = 0
    MOVE = 1

    NONE = 0
    
    LEFT = 1
    RIGHT = 2

    FORWARD = 1

    actions = {
        TURN: {
            "NONE":  NONE,
            "LEFT":  LEFT,
            "RIGHT": RIGHT,
        },
        MOVE: {
            "NONE":    NONE,
            "FORWARD": FORWARD,
        },
    }

    def __init__(
            self,
            marred=False,
            num_agents=1,
            num_powers=1,
            space_length=8,
            episode_length=64,
            seed=None,
    ):
        # Data types
        self.float_dtype = np.float32
        self.int_dtype = np.int32

        # Seeding
        self.np_random = np.random
        if seed is not None:
            self._seed(seed)
        
        assert episode_length > 0
        self.episode_length = episode_length

        # Create space
        self.space = SquareTiling(self.int_dtype, self.np_random, space_length, num_agents, num_powers)

        # Ensure that there is enough space for all agents and the goal
        assert num_agents < self.space.volume

        self.marred = marred

        # These will be set during reset (see below)
        self.time_step = None
        self.global_state = None

        # Defining observation and action spaces
        self.observation_space = None  # Note: this will be set via the env_wrapper
        self.action_space = {
            agent_id: gym.spaces.MultiDiscrete(
                tuple([len(action) for action in Realm.actions.values()])
            ) for agent_id in range(self.num_agents)
        }
    
    @property
    def num_agents(self):
        return self.space.num_agents
    
    @property
    def observations(self):
        return None

    @property
    def rewards(self):
        return None
    
    def _seed(self, seed=None):
        """
        Seeding the environment with a desired seed
        Note: this uses the code in
        https://github.com/openai/gym/blob/master/gym/utils/seeding.py
        """
        self.np_random.seed(seed)
        return [seed]

    def reset(self):
        # Reset the environment to its initial state
        self.space._space.fill(0)

        self.goal_point = self.space.get_unoccupied_point(self.space.agent_points)

        self.space._space[tuple(self.space.agent_points.T)] = np.arange(self.num_agents, dtype=self.int_dtype) + 2

        self.goal_reached = np.array([False]*self.num_agents, dtype=self.int_dtype)

        self.time_step = 0

        self.global_state = {}

        self.last_move_legal = [True]*self.num_agents

        self.first_action = [True]*self.num_agents

        return self.observations

    def step(self, actions=None):
        # Perform one step in the environment

        assert isinstance(actions, dict)
        assert len(actions) == self.num_agents

        for agent_id, action in actions.items():
            if 0 < action[Realm.MOVE]:
                match action[Realm.MOVE]:
                    case Realm.FORWARD:
                        delta = self.space.delta(self.space.agent_orientations[agent_id])
                        self.first_action[agent_id] = False
                        
                        new_point = np.clip(self.space.agent_points[agent_id] + delta, 0, np.array(self.space._space.shape) - 1, dtype=self.int_dtype)

                        if np.all(new_point == self.goal_point):
                            self.goal_reached[agent_id] = True
                        elif True:  # not self.occupied(new_point):
                            self.space._space[tuple(self.space.agent_points[agent_id].T)] = 0
                            self.space._space[tuple(new_point.T)] = agent_id + 2
                            self.space.agent_points[agent_id] = new_point
                            self.last_move_legal[agent_id] = True
                        else:    
                            self.last_move_legal[agent_id] = False
            else:
                match action[Realm.TURN]:
                    case Realm.LEFT:
                        self.space.agent_orientations[agent_id] -= 1
                        self.last_move_legal[agent_id] = True
                        self.first_action[agent_id] = False
                    case Realm.RIGHT:
                        self.space.agent_orientations[agent_id] += 1
                        self.last_move_legal[agent_id] = True
                        self.first_action[agent_id] = False
                
                self.space.agent_orientations[agent_id] %= self.space.SYMMETRY_ORDER

        obss = self.observations
        rewards = self.rewards
        done = any(self.goal_reached) or self.episode_length <= self.time_step
        info = None

        self.time_step += 1

        return obss, rewards, done, info

    def close(self):
        # Clean up resources
        pass

# Register the environment with OpenAI Gym
gym.register(
    id="Realm-v0",
    entry_point="realm:Realm",
)
